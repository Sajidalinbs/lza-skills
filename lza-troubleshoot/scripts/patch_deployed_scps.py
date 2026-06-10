#!/usr/bin/env python3
"""patch_deployed_scps.py — exempt stacksets-exec-* in ALREADY-DEPLOYED SCPs.

When the LZA enroll-accounts module re-attaches the quarantine SCP at the start
of the Accounts stage, a fresh `detach`/source-fix doesn't help fast enough —
the deployed policy CONTENT still carries the bad deny. This fetches each
customer-managed SCP via the Organizations API, adds the StackSets execution
role to its `ArnNotLike[aws:PrincipalArn]` allow-lists, and pushes the patched
content back with `update-policy`. SCP content is durable across re-attaches,
so this survives the pipeline re-attaching the policy.

Usage:
    python3 patch_deployed_scps.py --dry-run                 # show what would change
    python3 patch_deployed_scps.py                           # patch all customer SCPs
    python3 patch_deployed_scps.py --name Quarantine         # only this policy

Requires: boto3, credentials for the management account (organizations:*Policy).
"""
import argparse
import json
import sys

try:
    import boto3
    from botocore.exceptions import ClientError
except ImportError:
    sys.exit("boto3 required: pip install boto3")

EXEMPT_ARN = "arn:${PARTITION}:iam::*:role/stacksets-exec-*"
PRINCIPAL_KEY = "aws:PrincipalArn"
SCP_FILTER = "SERVICE_CONTROL_POLICY"


def _as_list(v):
    return v if isinstance(v, list) else [v]


def patch_document(doc) -> bool:
    changed = False
    for stmt in _as_list(doc.get("Statement", [])):
        if not isinstance(stmt, dict):
            continue
        cond = stmt.get("Condition")
        if not isinstance(cond, dict):
            continue
        for op in ("ArnNotLike", "ArnNotLikeIfExists"):
            block = cond.get(op)
            if not isinstance(block, dict) or PRINCIPAL_KEY not in block:
                continue
            arns = _as_list(block[PRINCIPAL_KEY])
            if EXEMPT_ARN not in arns:
                arns.append(EXEMPT_ARN)
                block[PRINCIPAL_KEY] = arns
                changed = True
    return changed


def iter_customer_scps(org, only_name=None):
    paginator = org.get_paginator("list_policies")
    for page in paginator.paginate(Filter=SCP_FILTER):
        for p in page["Policies"]:
            if p.get("AwsManaged"):
                continue  # never touch AWS-managed (e.g. FullAWSAccess)
            if only_name and p["Name"] != only_name:
                continue
            yield p


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--name", help="only patch the SCP with this exact name")
    ap.add_argument("--dry-run", action="store_true", help="show diffs, do not call update-policy")
    args = ap.parse_args()

    org = boto3.client("organizations")
    patched = scanned = 0

    for summary in iter_customer_scps(org, args.name):
        scanned += 1
        pid, name = summary["Id"], summary["Name"]
        detail = org.describe_policy(PolicyId=pid)["Policy"]
        try:
            doc = json.loads(detail["Content"])
        except json.JSONDecodeError as e:
            print(f"  SKIP {name} ({pid}): invalid JSON content — {e}")
            continue

        if not patch_document(doc):
            print(f"  ok (already exempt): {name} ({pid})")
            continue

        new_content = json.dumps(doc, separators=(",", ":"))
        if args.dry_run:
            print(f"  WOULD UPDATE: {name} ({pid})")
            continue
        try:
            org.update_policy(PolicyId=pid, Content=new_content)
            patched += 1
            print(f"  UPDATED: {name} ({pid})")
        except ClientError as e:
            print(f"  FAILED {name} ({pid}): {e}")

    if scanned == 0:
        print("no matching customer-managed SCPs found.")
    else:
        verb = "would update" if args.dry_run else "updated"
        print(f"\n{verb} {patched}/{scanned} customer-managed SCP(s).")


if __name__ == "__main__":
    main()
