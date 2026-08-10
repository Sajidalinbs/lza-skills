---
name: lza-troubleshoot
description: Use when an LZA pipeline run fails or behaves unexpectedly. Provides a structured diagnostic playbook for Control Tower baseline failures, SCP-blocked Account Factory operations, orphan IAM roles from partially-failed deploys, MISSING_PERMISSIONS_AF_PRODUCT pre-check failures, SSO/IAM Identity Center conflicts, Organizations API eventual-consistency traps, OU-rename CloudFormation logical-ID conflicts, and OU-delete ValidateEnvironmentConfig failures. Invoke at the moment of a pipeline failure to identify root cause and apply the fix.
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
| **Accounts** stage fails: `Baseline operation for "<ou-id>" ... in "FAILED" state` after the enroll module logs `OU "<ou-id>" has drifted. Resetting baseline...`; `get-baseline-operation` says *"failed to register an organizational unit due to pre-check failures"* | LZA's enroll-accounts creates a workload account, then immediately resets that account's **OU baseline**; CT's baseline pre-check runs against an account that's only seconds/minutes old → pre-check transient. Recurs once **per freshly-created account** (e.g. Dev, then Staging). Not a config error. | Wait for the account to settle, then reset that one OU's baseline directly: `aws controltower reset-enabled-baseline --enabled-baseline-identifier <enabledBaselineArn>` (find via `list-enabled-baselines`, filter `targetIdentifier` = the OU ARN). When all `list-enabled-baselines` show `SUCCEEDED`, retry the Accounts stage. Once **all** workload accounts exist, this stops recurring. |
| **Deploy** stage `SecurityResourcesStack-<acct>-<region>` rolls back: `MaxNumberOfConfigurationRecordersExceededException` (limit 1) and/or `MaxNumberOfDeliveryChannelsExceededException` | A **pre-existing AWS Config recorder + delivery channel** already occupies the 1-per-account-per-region limit in a governed region — typically the **management account in a workload region** where the customer ran their own Config (and Security Hub auto-created `securityhub-*` Config rules). LZA can't deploy its recorder. | **Back up** the existing setup (`describe-configuration-recorders`, `describe-delivery-channels`, rule names), then `stop-configuration-recorder` → `delete-delivery-channel` → `delete-configuration-recorder` in that account/region (customer-approved — it's their data plane observation only; the monitored resources are untouched and prior history in their bucket is retained). LZA recreates its own recorder delivering to the central LogArchive bucket. **Delete the rolled-back `SecurityResourcesStack` before retrying Deploy.** |
| `Stack [...] cannot be deleted while TerminationProtection is enabled` when cleaning up a failed LZA stack | LZA sets `terminationProtection: true` (global-config) on the stacks it creates, so rolled-back/failed LZA stacks can't be deleted directly. | Disable it first: `aws cloudformation update-termination-protection --no-enable-termination-protection --stack-name <name> --region <region>`, then `delete-stack`. (A `wait stack-delete-complete` after a *failed* `delete-stack` call returns success against the still-existing stack — re-`describe-stacks` to confirm it's actually gone.) |
| AWS Config queries from Audit return only Audit's own recorder | Per-account `select-resource-config` vs org-wide `select-aggregate-resource-config` (aggregator) confusion | Use the **aggregator** API, or Console → Config → Aggregators → Advanced query. |
| `AWS::ControlTower::EnabledControl <id><OUName>` `<ou-arn>\|<control-arn> already exists in stack` during the Deploy stage's OrganizationsStack update | An OU was renamed AFTER LZA had attached CT controls to it. LZA's CDK derives CFN logical IDs from OU names (`<control-id><OUNameCamelCased>`), so the rename produces NEW logical IDs that try to claim physical resources still owned by the OLD logical IDs in the same stack. CFN refuses. **Disabling the CT controls does NOT fix this** — CFN tracks ownership in stack state independently of whether the AWS-side resource exists. | **There is no graceful forward fix.** Recommended: revert the rename (rename OU back, re-enable any controls you disabled while diagnosing, `git revert` the rename commit, push). See "OU rename trap" runbook below. Avoid by pinning OU names at `/lza-plan` Decision 3 time. |
| `ValidateEnvironmentConfig` UPDATE_FAILED in the Prepare stack with `Organizational Unit '<name>' with id of '<ou-id>' was not found in the organization configuration.` after you removed an OU from `organization-config.yaml` | **LZA never deletes OUs implicitly.** Removing an OU from config is treated as a config drift error by the `ValidateEnvironmentConfig` Lambda, which runs *before* the Controls/Baseline stages that could otherwise tear down the OU's CT governance. The validator hard-fails the Prepare stack, so nothing else runs. | Manually deregister and delete the orphan OU(s) in this order, then re-run the pipeline (no config change needed): **(a)** disable all `EnabledControl` resources on each OU via `controltower:DisableControl`; **(b)** disable the CT `EnabledBaseline` via `controltower:DisableBaseline`; **(c)** `organizations:DeleteOrganizationalUnit`. Verify the OU is empty (no accounts, no child OUs) first. See "OU delete trap" runbook below. |
| **Prepare** stage CodeBuild (`*-ToolkitProject`) fails fast: `parsing network-config failed ... must have required property 'endpointPolicies'` | `network-config.yaml` is missing the **required top-level `endpointPolicies`** array. It's required whenever any `gatewayEndpoints`/`interfaceEndpoints` references a `defaultPolicy` (e.g. `Default`). Passes local YAML parsing but fails the pipeline's config-validator. | Add `endpointPolicies: [{ name: Default, document: vpc-endpoint-policies/default.json }]` (the doc ships in the AWS baseline), commit, push, re-run. See `/lza-configure` §6. |
| **Deploy** stage `RouteEntriesStack-<vpc>-<acct>-<region>` rolls back: `The route identified by 0.0.0.0/0 already exists` / `HandlerErrorCode: AlreadyExists` on an `AWS::EC2::Route` | A route was **renamed or had its target flipped** between deploys. LZA derives each route's CFN logical ID from its **route name** and models every route as its own `AWS::EC2::Route`; on update CFN **creates the new-named/retargeted route before deleting the old one**, but two routes can't share a destination in one table → collision. Surfaces table-by-table (ingress, then inspection, …). | **Don't rename route entries once deployed.** Recovery: don't hand-delete individual routes (leaves CFN drift where it won't recreate routes it still "owns"). Instead **delete the whole affected `RouteEntriesStack`** — disable termination protection first; the route *tables* live in a separate stack and survive — then retry Deploy; CDK recreates the stack cleanly. For a target flip on a route table with live workloads, schedule it (brief routing gap during recreate). |
| CT landing zone in **FAILED**; `get-landing-zone-operation` statusMessage: *"the assumed role, **AWSServiceRoleForSSO**, doesn't have permission to perform the operation 'unknown operation'"* (Prepare stage, `accelerator-control-tower` module) | The `AWSServiceRoleForSSO` service-linked role was (re)created during CT landing-zone setup — commonly right after **deleting a pre-existing IDC instance** in `/lza-bootstrap` Step 8 — and IAM hadn't propagated it before CT used it. Eventual-consistency race, **not** a config error. | Verify the SLR now exists (`aws iam get-role --role-name AWSServiceRoleForSSO`) and an org IDC instance is present (`sso-admin list-instances`); then **`aws controltower reset-landing-zone --landing-zone-identifier <arn>`**, wait for `SUCCEEDED`, then retry the pipeline's Prepare stage. See "CT landing zone AWSServiceRoleForSSO race" runbook below. |
| `AWSAccelerator-InstallerStack` (the installer) sits ~1h then **ROLLBACK_COMPLETE**; failed resource `Custom::GetPrefixes` (or `ValidateInstaller`): *"CloudFormation did not receive a response from your Custom Resource"*; Lambda log shows `Status: timeout` at `Duration: 3000.00 ms` | The LZA 1.15.0 installer template ships two helper Lambdas (`ResourceNamePrefixes*`, `ValidateInstaller*`) at **Timeout=3s / Memory=128MB** on `nodejs22.x`. SDK init + first SSM call exceed 3s, so they never respond; CFN waits the full ~1h custom-resource timeout, then rolls back. | Patch the template: set those two Lambdas to **`Timeout: 120`, `MemorySize: 1024`**. Template is >51KB so upload to S3 and redeploy via `--template-url` (not inline `--template-body`). Delete the rolled-back stack first. See "Installer Lambda 3s timeout" runbook below. |

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

### CT landing zone AWSServiceRoleForSSO race

Symptom: the Prepare stage's `accelerator-control-tower` module reports the CT landing zone operation in `FAILED`, and `get-landing-zone-operation` shows *"the assumed role, AWSServiceRoleForSSO, doesn't have permission to perform the operation 'unknown operation'."*

Cause: CT enabled org-level IDC and **created the `AWSServiceRoleForSSO` service-linked role as part of the same operation**, then tried to use it to provision the shared accounts within ~3 minutes — before IAM propagated it. This very commonly follows **deleting a pre-existing IDC instance** during `/lza-bootstrap` Step 8 (the delete had removed the SLR). It's an eventual-consistency race; everything is fine on retry.

Fix:
1. Confirm the dependencies now exist and have propagated:
   - `aws iam get-role --role-name AWSServiceRoleForSSO` (should return the role + `AWSSSOServiceRolePolicy`).
   - `aws sso-admin list-instances` (an org IDC instance should be present).
   - `aws organizations list-aws-service-access-for-organization` (shows `sso.amazonaws.com`).
2. Check landing-zone status: `aws controltower get-landing-zone --landing-zone-identifier <arn>` → `FAILED`.
3. **Reset** (re-applies LZA's stored manifest): `aws controltower reset-landing-zone --landing-zone-identifier <arn>` → poll `get-landing-zone-operation` until `SUCCEEDED` (~30–60 min).
4. Retry the pipeline: `aws codepipeline retry-stage-execution --pipeline-name <prefix>-Pipeline --stage-name Prepare --pipeline-execution-id <id> --retry-mode FAILED_ACTIONS` (or push any change to re-trigger). With a healthy landing zone it proceeds to Accounts/Bootstrap.

Prevent next time: in `/lza-bootstrap` Step 8, after deleting an old IDC instance, **pre-create the SLR** (`aws iam create-service-linked-role --aws-service-name sso.amazonaws.com`) and wait a few minutes before the pipeline reaches CT setup.

### Installer Lambda 3s timeout (installer stack rollback)

Symptom: `AWSAccelerator-InstallerStack` stays `CREATE_IN_PROGRESS` for ~1 hour, then `ROLLBACK_COMPLETE`. The failed resource is `Custom::GetPrefixes` (`ResourceNamePrefixes*`) or `ValidateInstaller*` with *"CloudFormation did not receive a response from your Custom Resource."* That Lambda's CloudWatch log shows repeated `REPORT ... Duration: 3000.00 ms ... Status: timeout`.

Cause: the LZA 1.15.0 installer template provisions those two helper Lambdas with the CloudFormation **defaults Timeout=3s / MemorySize=128MB** on `nodejs22.x`. At 128MB the SDK v3 init + SSM call can't finish in 3s (cold-start init alone observed ~9.6s), so the function never sends its cfn-response and CFN waits out the full custom-resource timeout before failing.

Fix (patch the template, redeploy):
1. Download the installer template: `https://solutions-reference.s3.amazonaws.com/landing-zone-accelerator-on-aws/v1.15.0/AWSAccelerator-InstallerStack.template`.
2. For every `AWS::Lambda::Function` with `Timeout` 3 / `MemorySize` 128, set `Timeout: 120` and `MemorySize: 1024` (only `ResourceNamePrefixes*` and `ValidateInstaller*` ship that way). Logic unchanged.
3. The template is ~72KB (>51,200B inline limit), so upload to S3 and deploy via `--template-url` (not `--template-body`).
4. Delete the rolled-back stack first (`delete-stack` + `wait stack-delete-complete`), then `create-stack` with the same parameters.

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

### OU delete trap (`ValidateEnvironmentConfig` orphan-OU failure)

> ⚠️ **LZA never deletes OUs implicitly.** Removing an OU from `organization-config.yaml` is a config-drift error, not a delete instruction. Clean up CT governance first, then the OU, then re-run.

**What it looks like.** The Prepare stack's `Custom::ValidateEnvironmentConfiguration` resource fails with:

```
UPDATE_FAILED  Custom::ValidateEnvironmentConfiguration  ValidateEnvironmentResource
Received response status [FAILED] from custom resource. Message returned:
  Organizational Unit '<OU/Path>' with id of '<ou-id>' was not found in the organization configuration.
```

The Prepare stack then rolls back and the pipeline halts before the Organizations/Controls/Baseline stages — which is precisely why LZA can't clean up the OU on your behalf: it never gets the chance.

**Why it happens.** Two reinforcing constraints:

1. The validator runs **before** the stages that would normally tear down CT governance on the OU.
2. AWS Organizations refuses `DeleteOrganizationalUnit` on any OU that is registered with Control Tower (an `EnabledBaseline` is attached, or `EnabledControl`s exist).

So even if the validator were silent, AWS would still reject the delete. Both paths converge on manual cleanup.

**Pre-checks before cleanup.** Confirm the OU is genuinely safe to delete:

```bash
PROFILE=<mgmt-profile>; REGION=<home-region>; OU_ID=<orphan-ou-id>
ORG_ID=$(aws organizations describe-organization --profile $PROFILE --region $REGION --query 'Organization.Id' --output text)
MGMT=$(aws sts get-caller-identity --profile $PROFILE --region $REGION --query 'Account' --output text)
OU_ARN="arn:aws:organizations::${MGMT}:ou/${ORG_ID}/${OU_ID}"

aws organizations list-accounts-for-parent --parent-id $OU_ID --profile $PROFILE --region $REGION
aws organizations list-organizational-units-for-parent --parent-id $OU_ID --profile $PROFILE --region $REGION
aws controltower list-enabled-controls --target-identifier "$OU_ARN" --profile $PROFILE --region $REGION
aws controltower list-enabled-baselines --filter targetIdentifiers="$OU_ARN" --profile $PROFILE --region $REGION
```

If `list-accounts-for-parent` or `list-organizational-units-for-parent` return anything, **STOP** — move/relocate them first via a separate change (account-move is non-destructive; deleting an OU with children is not allowed by AWS anyway).

**Cleanup order (per OU).**

1. **Disable all `EnabledControl`s** on the OU. Controls within a single OU can be disabled in parallel.
2. **Wait for every disable-control op to reach `SUCCEEDED`.**
3. **Disable the `EnabledBaseline`** on the OU. ⚠️ **Control Tower serializes baseline operations org-wide** — only one baseline op can be in flight across the entire Organization, even across different OUs. If you're cleaning up multiple OUs, **serialize the baseline disables** (or expect `ConflictException: AWS Control Tower cannot perform the requested baseline operation because another operation is in progress.` and retry).
4. **Wait for the disable-baseline op to reach `SUCCEEDED`** (~1–2 min).
5. **Delete the OU** via `organizations:DeleteOrganizationalUnit`. Instant.

**Reference automation.** A complete orchestrator that handles parallel control-disable, the baseline serialization gotcha, and ordered OU deletion is in `scripts/cleanup_empty_ous.py`. The shape:

```python
# Per-OU sequence (run multiple OUs concurrently for steps 1–2; serialize step 3 across OUs):
controls = aws controltower list-enabled-controls --target-identifier $OU_ARN
parallel:                                                                    # step 1
  for c in controls: aws controltower disable-control --control-identifier $c --target-identifier $OU_ARN
wait_all(op_ids, get-control-operation → SUCCEEDED)                          # step 2
aws controltower disable-baseline --enabled-baseline-identifier $BASELINE    # step 3 (serialize across OUs)
wait(op_id, get-baseline-operation → SUCCEEDED)                              # step 4
aws organizations delete-organizational-unit --organizational-unit-id $OU_ID # step 5
```

**Re-run.** Once both `Workloads/Dev` and `Workloads/Test` (or whichever OUs you removed from config) are gone from AWS Organizations, **no config change is needed** — re-trigger the pipeline:

```bash
aws codepipeline start-pipeline-execution --name AWSAccelerator-Pipeline --profile $PROFILE --region $REGION
```

The validator will now see zero orphans and pass.

**Why this isn't symmetric with OU creation.** LZA creates OUs declaratively because creation is non-destructive. It refuses to delete declaratively because OU deletion can orphan accounts, drop policy enforcement, and is irreversible — a config typo causing accidental OU loss would be catastrophic. The asymmetry is deliberate.

**Prevention / sequencing for OU restructure work.** When you need to retire OUs as part of a larger restructure, run it as a two-phase change:

1. **Phase 1 (config + pipeline):** Add the new OUs to config, move all accounts out of the to-be-retired OUs into the new ones. Pipeline succeeds — old OUs are now empty.
2. **Phase 2 (manual cleanup + pipeline):** Cleanup-then-remove. Either:
   - **Option A (preferred):** Manually disable controls + baseline + delete the empty OU(s), THEN remove them from config and push. Pipeline succeeds cleanly.
   - **Option B (acceptable):** Remove from config + push first, hit the validator failure (this trap), then do the manual cleanup, then re-run. Same end state, one extra pipeline failure on the record.

Document this sequence in the customer-facing change plan; the cleanup step is operator work that LZA cannot automate.

---

## Bundled scripts (`scripts/`)

| Script | Purpose |
|---|---|
| `patch_scps.py` | Patch SCP **source** JSON files — add `stacksets-exec-*` to every `ArnNotLike` allow-list |
| `patch_deployed_scps.py` | Patch **deployed** SCP content in-place via the Organizations `update-policy` API |
| `find_precheck_failure.sh` | CloudTrail one-liner to find the `PrecheckOrganizationalUnit` failure event |
| `delete_orphan_ct_role.sh` | Clean up an orphan `AWSControlTowerExecution` role in a member account |
| `cleanup_empty_ous.py` | Tear down empty OUs that `ValidateEnvironmentConfig` is complaining about: disable CT controls + baseline + delete OU, with the baseline-serialization gotcha handled |

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
