"""Tear down empty OUs that LZA's ValidateEnvironmentConfig refuses to delete.

Use this when you removed an OU from organization-config.yaml and the
Prepare stack fails with:

    Organizational Unit '<path>' with id of '<ou-id>' was not found in the
    organization configuration.

Order per OU:
  1. Disable all EnabledControls (parallel within each OU)
  2. Wait for control-disable ops to finish
  3. Disable the EnabledBaseline
  4. Wait for the baseline-disable op to finish
  5. Delete the OU via Organizations API

⚠️ Control Tower serializes baseline operations org-wide. When cleaning up
   multiple OUs concurrently, the second baseline-disable will hit
   ConflictException. This script catches that and retries; if you adapt it,
   keep the retry or run OUs sequentially through step 3.

Pre-flight (run yourself before calling this script):
  - Confirm OU is empty (no accounts, no child OUs)
  - You have credentials in the management account with
    organizations:* and controltower:* permissions

Edit TARGETS, PROFILE, REGION, MGMT_ACCT, ORG_ID below for your environment.
"""
import json
import subprocess
import sys
import time
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed

PROFILE = "<mgmt-profile>"      # e.g. acme-mgmt-iam
REGION = "<home-region>"        # e.g. eu-central-1
MGMT_ACCT = "<mgmt-account-id>" # 12-digit management account id
ORG_ID = "<o-...>"              # aws organizations describe-organization --query 'Organization.Id'

# Fill one entry per OU to retire. Get baseline_arn from:
#   aws controltower list-enabled-baselines \
#     --filter targetIdentifiers=arn:aws:organizations::<MGMT>:ou/<ORG_ID>/<OU_ID> \
#     --query 'enabledBaselines[0].arn'
TARGETS = [
    # {"ou_id": "ou-xxxx-yyyyyyyy", "name": "Workloads/Dev",
    #  "baseline_arn": "arn:aws:controltower:<region>:<mgmt>:enabledbaseline/XXXX"},
]

# How many baseline ops to allow in flight at once. Control Tower serializes
# baseline ops org-wide, so keep at 1.
BASELINE_CONCURRENCY = 1

print_lock = threading.Lock()
baseline_sem = threading.Semaphore(BASELINE_CONCURRENCY)

def say(msg):
    with print_lock:
        print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)

def aws(args):
    cmd = ["aws"] + args + ["--profile", PROFILE, "--region", REGION]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"aws {' '.join(args[:3])} failed: {r.stderr.strip()}")
    return r.stdout

def ou_arn(ou_id):
    return f"arn:aws:organizations::{MGMT_ACCT}:ou/{ORG_ID}/{ou_id}"

def list_controls(target_arn):
    out = aws(["controltower", "list-enabled-controls", "--target-identifier", target_arn])
    return [c["controlIdentifier"] for c in json.loads(out)["enabledControls"]]

def disable_control(control_arn, target_arn, name):
    out = aws(["controltower", "disable-control",
               "--control-identifier", control_arn,
               "--target-identifier", target_arn])
    op_id = json.loads(out)["operationIdentifier"]
    say(f"  {name}: disable-control sent {control_arn.split('/')[-1]} (op {op_id[:8]}...)")
    return op_id

def wait_control_op(op_id, name):
    while True:
        out = aws(["controltower", "get-control-operation", "--operation-identifier", op_id])
        status = json.loads(out)["controlOperation"]["status"]
        if status == "SUCCEEDED":
            return
        if status == "FAILED":
            raise RuntimeError(f"{name}: disable-control op {op_id} FAILED")
        time.sleep(10)

def disable_baseline(baseline_arn, name):
    # Serialize across OUs to avoid ConflictException
    with baseline_sem:
        # Retry on ConflictException in case something else (e.g. another tool) raced us
        for attempt in range(6):
            try:
                out = aws(["controltower", "disable-baseline", "--enabled-baseline-identifier", baseline_arn])
                op_id = json.loads(out)["operationIdentifier"]
                say(f"  {name}: disable-baseline sent (op {op_id[:8]}...)")
                return op_id
            except RuntimeError as e:
                if "ConflictException" in str(e) and attempt < 5:
                    say(f"  {name}: baseline conflict, retrying in 30s (attempt {attempt + 1}/5)")
                    time.sleep(30)
                    continue
                raise

def wait_baseline_op(op_id, name):
    while True:
        out = aws(["controltower", "get-baseline-operation", "--operation-identifier", op_id])
        status = json.loads(out)["baselineOperation"]["status"]
        if status == "SUCCEEDED":
            return
        if status == "FAILED":
            raise RuntimeError(f"{name}: disable-baseline op {op_id} FAILED")
        time.sleep(10)

def delete_ou(ou_id, name):
    aws(["organizations", "delete-organizational-unit", "--organizational-unit-id", ou_id])
    say(f"  {name}: OU {ou_id} DELETED")

def process_ou(target):
    name = target["name"]
    ou_id = target["ou_id"]
    target_arn = ou_arn(ou_id)
    say(f"START {name} ({ou_id})")

    controls = list_controls(target_arn)
    say(f"  {name}: {len(controls)} controls to disable")

    op_ids = []
    with ThreadPoolExecutor(max_workers=max(1, len(controls))) as ex:
        futs = [ex.submit(disable_control, c, target_arn, name) for c in controls]
        for f in as_completed(futs):
            op_ids.append(f.result())

    say(f"  {name}: waiting for {len(op_ids)} control-disable ops...")
    with ThreadPoolExecutor(max_workers=max(1, len(op_ids))) as ex:
        futs = [ex.submit(wait_control_op, op, name) for op in op_ids]
        for f in as_completed(futs):
            f.result()
    say(f"  {name}: all controls disabled")

    bop = disable_baseline(target["baseline_arn"], name)
    wait_baseline_op(bop, name)
    say(f"  {name}: baseline disabled")

    delete_ou(ou_id, name)

def main():
    if not TARGETS:
        print("ERROR: TARGETS list is empty. Edit the script and add one entry per OU to retire.", file=sys.stderr)
        sys.exit(2)
    if "<" in PROFILE or "<" in REGION or "<" in MGMT_ACCT or "<" in ORG_ID:
        print("ERROR: PROFILE/REGION/MGMT_ACCT/ORG_ID still contain placeholders.", file=sys.stderr)
        sys.exit(2)

    start = time.time()
    failed = False
    with ThreadPoolExecutor(max_workers=len(TARGETS)) as ex:
        futs = {ex.submit(process_ou, t): t for t in TARGETS}
        for f in as_completed(futs):
            try:
                f.result()
            except Exception as e:
                failed = True
                say(f"FAILED: {e}")

    elapsed = int(time.time() - start)
    print(f"\nDone in {elapsed // 60}m{elapsed % 60}s. {'NOT all OK' if failed else 'All OK.'}")
    sys.exit(1 if failed else 0)

if __name__ == "__main__":
    main()
