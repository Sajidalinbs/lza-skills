---
name: lza-troubleshoot
description: Use when an LZA pipeline run fails or behaves unexpectedly. Provides a structured diagnostic playbook for Control Tower baseline failures, SCP-blocked Account Factory operations, orphan IAM roles from partially-failed deploys, MISSING_PERMISSIONS_AF_PRODUCT pre-check failures, SSO/IAM Identity Center conflicts, Organizations API eventual-consistency traps, and OU-rename CloudFormation logical-ID conflicts. Invoke at the moment of a pipeline failure to identify root cause and apply the fix.
---

# `/lza-troubleshoot` — Diagnostic playbook for LZA pipeline failures

> **Validated against LZA version:** 1.15.0
> **Use anytime — not tied to a specific deployment phase**

## Purpose

LZA error messages are notoriously generic. The pipeline failure log often shows nothing more than `Baseline operation FAILED` — the root cause is buried in CloudTrail, CloudFormation StackSet status, or SCP evaluation. This skill is the operator's diagnostic playbook for getting from "pipeline failed" to "I know exactly what's wrong and how to fix it."

## How to use this skill

1. Note the **failing stage** (from `/lza-deploy`'s stage map) and the exact error string.
2. Run the **3-API diagnostic flow** to find the real cause.
3. Match the symptom in the **Symptom → Root cause → Fix** table.
4. Apply the fix (scripts in `scripts/` automate the fiddly ones), then re-run via `/lza-deploy`.

> ⚠️ Several fixes touch IAM roles and SCPs in the management/member accounts. Have the **break-glass access** from `/lza-bootstrap` Step 3 confirmed working before you disable SSO trusted access or delete roles.

---

## Step 0 — AWS credential preflight (before any AWS command)

Every diagnostic and fix below runs the AWS CLI against the **management account** in the **HomeRegion**. Diagnosing the wrong account/region (or hitting an expired SSO session mid-fix) wastes time and can mask the real cause — verify first:

```bash
aws sts get-caller-identity     # Account + ARN — who am I?
aws configure list              # active profile + region
```

Confirm against `<customer>-lza-plan.md`: **Account == Management account**, **Region == HomeRegion**.

```bash
aws sso login --profile <customer>-mgmt
export AWS_PROFILE=<customer>-mgmt AWS_REGION=<HomeRegion>
```

Troubleshooting needs **scoped admin in the management account** for the SCP/IAM fixes; some scripts (e.g. `delete_orphan_ct_role.sh`) assume from the management account **into a member account** via the `AWSControlTowerExecution` role — so the active identity must be allowed to assume it. Never store creds in the repo; prefer temporary SSO credentials.

---

## The 3-API diagnostic flow

For any Control-Tower-related failure, these three calls almost always surface the real cause:

**1. Baseline operation details** — what operation, what status message:
```bash
aws controltower get-baseline-operation --operation-identifier <id>
```

**2. StackSet instance status** — per-account / per-region failure with the actual IAM/CFN error:
```bash
aws cloudformation list-stack-instances --stack-set-name AWSControlTowerExecutionRole \
  --query 'Summaries[?Status==`OUTDATED` || StatusReason!=`null`]'
```

**3. CloudTrail pre-check event** — reveals the `failedPrechecks` array naming the exact pre-check:
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=PrecheckOrganizationalUnit \
  --max-results 5
# or use scripts/find_precheck_failure.sh <minutes-back>
```

The pre-check event is the single most useful artifact — `failedPrechecks` tells you precisely which guardrail/permission/state check blocked the operation.

---

## Symptom → Root cause → Fix index

| Symptom | Root cause | Fix |
|---|---|---|
| `AWS Control Tower Landing Zone cannot deploy because AWS Organizations have services enabled` | A trusted service is already enabled in Organizations — commonly `sso.amazonaws.com` from a pre-existing IAM Identity Center | `disable-aws-service-access` for the conflicting principal(s). **Document the SSO outage window** for the customer first. See the SSO runbook below. |
| `Baseline operation FAILED` + StackSet shows `User: ...stacksets-exec-... is not authorized to perform: iam:CreateRole` + `explicit deny in a service control policy` | A quarantine/guardrail SCP doesn't exempt `stacksets-exec-*` (StackSets' service-managed execution role) | Patch **every** customer-managed SCP to allow `arn:${PARTITION}:iam::*:role/stacksets-exec-*`. Fix **source files** (`scripts/patch_scps.py`) **and** deployed policies (`scripts/patch_deployed_scps.py`). |
| `Resource of type 'AWS::IAM::Role' with identifier 'AWSControlTowerExecution' already exists` | Orphan role left in a member account from a previously partially-failed CT deploy | Assume into the member account, detach `AdministratorAccess`, `delete-role`; let CT recreate. `scripts/delete_orphan_ct_role.sh <account-id>`. |
| `MISSING_PERMISSIONS_AF_PRODUCT` in the PrecheckOrganizationalUnit event | LZA pipeline role isn't associated with the Service Catalog Account Factory portfolio (usually after a CT redeploy) | `aws servicecatalog associate-principal-with-portfolio --portfolio-id <af-portfolio> --principal-arn <pipeline-codebuild-role>` |
| Same failure repeats after you fixed the SCP → SCP "reverted" | The enroll-accounts module **re-attaches** the quarantine SCP at the start of Accounts; deploy stage re-applies the OLD content | Push fixed SCP **content** with `update-policy` (not just `detach-policy`). Content is durable across re-attaches. Use `scripts/patch_deployed_scps.py`. |
| `detach-policy` reports success but `list-targets-for-policy` still shows it attached | Organizations API **eventual consistency** between the per-policy and per-target views | Trust the **per-target** view (`list-policies-for-target`) — it's ground truth. The per-policy view catches up within minutes. |
| `Account is not in ACTIVE state` pre-check | Newly created account still initializing (`PENDING_CLOSURE`/`SUSPENDED` transient) | Wait 2–5 min, re-run. AWS-side latency, not a config error. |
| AWS Config queries from Audit return only Audit's own recorder | Per-account `select-resource-config` vs org-wide `select-aggregate-resource-config` (aggregator) confusion | Use the **aggregator** API, or Console → Config → Aggregators → Advanced query. |
| `AWS::ControlTower::EnabledControl <id><OUName>` `<ou-arn>\|<control-arn> already exists in stack` during the Deploy stage's OrganizationsStack update | An OU was renamed AFTER LZA had attached CT controls to it. LZA's CDK derives CFN logical IDs from OU names (`<control-id><OUNameCamelCased>`), so the rename produces NEW logical IDs that try to claim physical resources still owned by the OLD logical IDs in the same stack. CFN refuses. **Disabling the CT controls does NOT fix this** — CFN tracks ownership in stack state independently of whether the AWS-side resource exists. | **There is no graceful forward fix.** Recommended: revert the rename (rename OU back, re-enable any controls you disabled while diagnosing, `git revert` the rename commit, push). See "OU rename trap" runbook below. Avoid by pinning OU names at `/lza-plan` Decision 3 time. |

---

## Deep-dive runbooks

### SSO / IAM Identity Center trusted-access disable

The trap from `/lza-bootstrap` Step 2/8. Before disabling `sso.amazonaws.com` trusted access:

1. **Confirm break-glass works** (root + IAM break-glass user, `/lza-bootstrap` Step 3) — disabling SSO can drop your own console access.
2. **Inventory** existing permission sets + account assignments (you may need to recreate them).
3. **Announce the outage window** to the customer — active SSO sessions will break.
4. Disable: `aws organizations disable-aws-service-access --service-principal sso.amazonaws.com`.
5. Re-run the pipeline; let CT/LZA establish IDC fresh.
6. **Recovery:** recreate permission sets/assignments per your inventory; re-test SSO login.

### SCP exemption patch (source files)

`scripts/patch_scps.py` walks `service-control-policies/*.json` and adds `arn:${PARTITION}:iam::*:role/stacksets-exec-*` to every `ArnNotLike[aws:PrincipalARN]` allow-list. Run it, commit the changed policy files, then deploy.

### Deployed SCP in-place update

`scripts/patch_deployed_scps.py` fetches each deployed SCP via the Organizations API, applies the same exemption, and pushes it back with `update-policy`. Use this when the pipeline re-attaches old SCP content faster than a fresh deploy can fix it.

### CloudTrail pre-check lookup

`scripts/find_precheck_failure.sh <minutes-back>` runs the exact `lookup-events` invocation for `PrecheckOrganizationalUnit` in the failure window and prints the `failedPrechecks` array.

### Orphan role cleanup

`scripts/delete_orphan_ct_role.sh <account-id>` assumes into the member account via `AWSControlTowerExecution`, lists attached policies, detaches `AdministratorAccess`, and deletes the orphan role so CT can recreate it cleanly.

### OU rename trap (`*WorkloadsX` → `*WorkloadsY` CFN conflict)

> ⚠️ **There is no graceful forward fix.** Don't rename OUs after CT controls are attached. If you already did — revert.

**What it looks like.** The Deploy stage's `AWSAccelerator-OrganizationsStack-<acct>-<region>` update fails with one or more entries of:

```
CREATE_FAILED  AWS::ControlTower::EnabledControl  <control-id><OUNameQa>
<ou-arn>|<control-arn> already exists in stack <stack-arn>
```

**Why it happens.** LZA's CDK derives CFN logical IDs from OU names — `<control-id><OUNameCamelCased>` (e.g. `497wrm2xnk1wxlf4obrdo7mejWorkloadsQa`). When you rename `Workloads/Test` → `Workloads/QA`:

1. Synth produces a NEW template with `*WorkloadsQa` logical IDs
2. CFN diff = "ADD `*WorkloadsQa` + REMOVE `*WorkloadsTest`"
3. CFN's default update ordering: CREATE first, DELETE second (to minimize disruption)
4. `*WorkloadsQa` tries to claim physical ID `<OU-ARN>|<control-ARN>`
5. CFN refuses — `*WorkloadsTest` in the same stack still owns that physical ID

**Disabling the CT controls does NOT fix this.** CFN tracks resource ownership in stack state independently of whether the AWS-side resource exists. Disabling controls leaves CFN's ownership binding intact; the next pipeline run hits the same "already exists in stack" error.

**Why this is so hard to fix forward:**

| Forward path | Why it's complex |
|---|---|
| Wait for CFN to delete-then-create | CFN's default is create-first; no API to flip the order |
| `cloudformation continue-update-rollback --resources-to-skip` | Only works in `UPDATE_ROLLBACK_FAILED`, not `UPDATE_ROLLBACK_COMPLETE` |
| `cloudformation update-stack --resources-to-import` | Requires hand-crafting a template that imports existing physical resources into new logical IDs — bypasses LZA's synth; high risk of drift |
| Nuke the OrganizationsStack | Destroys ALL SCPs, RCPs, tag/backup policies, CT controls — full enforcement gap during the gap |

**Recommended fix: revert.**

```bash
OU_ID=<the-renamed-OU-id>
OLD_NAME=Test               # or whatever it was before the rename
NEW_NAME=QA                 # the new name you tried
COMMIT=<rename-commit-sha>  # the commit that renamed in config

# 1. If you disabled any CT controls while diagnosing, re-enable them
#    so CFN state and AWS-side state are consistent again.
for c in <control-id-1> <control-id-2> ... ; do
  aws controltower enable-control \
    --control-identifier "arn:aws:controlcatalog:::control/$c" \
    --target-identifier "arn:aws:organizations::<mgmt-acct>:ou/<org-id>/$OU_ID" \
    --profile <mgmt-profile> --region <home-region> \
    --query 'operationIdentifier' --output text
done

# 2. Wait for all controls to return to SUCCEEDED.

# 3. Rename the OU back to its original name.
aws organizations update-organizational-unit \
  --organizational-unit-id $OU_ID \
  --name $OLD_NAME \
  --profile <mgmt-profile> --region <home-region>

# 4. Revert the rename commit and push.
git revert --no-edit $COMMIT
git push

# 5. Pipeline auto-triggers on the push. Synth produces template
#    identical to what's deployed — no diff for the CT controls.
#    Deploy stage should succeed.
```

**Prevention.** This trap is now flagged in `/lza-plan` Decision 3 (OU structure):

> OU names are effectively permanent. CT controls attached to an OU derive their CFN logical IDs from the OU name. Renaming an OU after CT controls are attached creates an unresolvable CFN logical-ID conflict. Decide OU names at planning time and treat them as immutable.

If the customer asks for an OU rename post-deployment, push back hard. The realistic answer is "we can't, but we can rename the *account* if that addresses the underlying dissonance" — account aliases are mutable; OUs after CT attachment are not.

---

## Bundled scripts (`scripts/`)

| Script | Purpose |
|---|---|
| `patch_scps.py` | Patch SCP **source** JSON files — add `stacksets-exec-*` to every `ArnNotLike` allow-list |
| `patch_deployed_scps.py` | Patch **deployed** SCP content in-place via the Organizations `update-policy` API |
| `find_precheck_failure.sh` | CloudTrail one-liner to find the `PrecheckOrganizationalUnit` failure event |
| `delete_orphan_ct_role.sh` | Clean up an orphan `AWSControlTowerExecution` role in a member account |

> All scripts are **read-what-they-do before running** — they modify SCPs and IAM. Run with credentials scoped to the management account (and the target member account for the role cleanup). Dry-run flags are provided where destructive.

---

## When to re-invoke this skill

- The moment any `/lza-deploy` stage fails.
- When `/lza-validate` surfaces a red check (drift, missing delegation, stuck quarantine).
- When `/lza-add-account` leaves a new account stuck mid-quarantine.

## Related skills

- `/lza-deploy` — the stage map that tells you *where* it failed
- `/lza-validate` — the checks that surface latent problems to bring here
- `/lza-bootstrap` — Steps 2/3/8 are the prerequisites that prevent the worst traps
- Add to this file as you discover new failure modes in the field (see README "Contributing").
