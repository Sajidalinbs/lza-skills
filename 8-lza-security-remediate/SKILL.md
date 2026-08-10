---
name: lza-security-remediate
description: Use after an LZA deployment when Security Hub / a CIS scanner shows findings on accelerator resources, or when existing suppression rules are silently not firing. Provides a remediation playbook for Security Hub automation-rule suppression (incl. the AcceleratorPrefix vs AWSAccelerator mismatch), classifying findings as LZA-created vs not, deploying the CIS section-4 CloudWatch metric filters/alarms, enabling Amazon Inspector org-wide (LZA has no native support), AWS Backup plan coverage, and producing a suppression risk register. Invoke when triaging Security Hub noise or hardening a freshly-deployed landing zone.
---

# `/lza-security-remediate` — Security Hub finding remediation & suppression

> **Validated against LZA version:** 1.15.0
> **Use anytime after `/lza-deploy` — pairs with `/lza-validate` (which surfaces the findings) and `/lza-troubleshoot` (pipeline failures, not findings).**

## Purpose

A green pipeline produces hundreds of Security Hub findings. Most on LZA-managed resources are
**by-design** and should be suppressed; some are **real gaps** the accelerator doesn't close
(CIS monitoring, Inspector, backups); and a frustrating subset are suppression rules that were
*written* but silently **never fire**. This skill takes you from "a wall of findings" to "every
finding is either passing, suppressed-with-a-reason, or on a tracked risk register."

The #1 trap: **suppression rules that match `{{ AcceleratorPrefix }}` (e.g. `acme`) when the
LZA framework was actually installed with the default `AWSAccelerator` prefix** — so the rules
match nothing and the findings stay `NEW`. See §2.

## How to use this skill

1. **Preflight** credentials (Step 0) — most "missing finding" confusion is wrong account/region.
2. **Audit** which suppression rules actually fire (`scripts/audit_suppressions.sh`).
3. **Diagnose** the prefix/tag mismatch (§2) — the usual reason rules don't fire.
4. For each remaining finding, **classify** it: LZA-created → suppress; not → fix or risk-accept (§3, §4).
5. Apply the **config fixes** to `security-config.yaml`, validate, commit, let the pipeline deploy.
6. Close the **real gaps**: CIS-4 monitoring (§5), Inspector (§6), Backup (§7).
7. Produce the **risk register** (§8) and remember **rules aren't retroactive** (§9).

> ⚠️ All suppression/monitoring config lands in `security-config.yaml` and only takes effect
> **after the pipeline redeploys**. Automation rules act only on findings created/updated *after*
> the rule exists — existing `NEW` findings need a bulk flip (§9).

---

## Step 0 — AWS credential preflight (before any AWS command)

Security Hub aggregates in the **delegated admin (Audit) account**, **HomeRegion**. Org/account
queries run in the **management account**. Wrong account/region (or per-account vs aggregator
confusion) is the #1 source of "the finding isn't there" / "the rule isn't working" mistakes.

```bash
aws sts get-caller-identity     # who am I?
aws configure list              # active profile + region
```

Confirm against `<customer>-lza-plan.md`. Typical flow — start in management, assume into Audit:

```bash
aws sso login --profile <customer>-mgmt
export AWS_PROFILE=<customer>-mgmt AWS_REGION=<HomeRegion>

# Assume into Audit (delegated security admin) for Security Hub / Inspector aggregation:
CREDS=$(aws sts assume-role --role-arn arn:aws:iam::<AUDIT_ACCT>:role/AWSControlTowerExecution \
  --role-session-name sec-remediate --query Credentials --output json)
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_SESSION_TOKEN=...   # from $CREDS
```

The `delegatedAdminAccount` for security services is in `security-config.yaml`
(`centralSecurityServices.delegatedAdminAccount`, normally `Audit`). Get its account id from
`accounts-config.yaml` / `organizations:list-accounts`. Never store creds in the repo.

---

## 1 — Audit which suppressions actually fire

Before changing anything, measure. For every control you suppress, compare `SUPPRESSED` vs
`NEW` in the **Audit aggregator**:

```bash
scripts/audit_suppressions.sh <HomeRegion>
```

Reading the output:

- Control shows **only `SUPPRESSED` / `RESOLVED`** → rule works. ✅
- Control shows **`NEW` findings that should be covered** → rule is **not matching** → go to §2.
- Mixed (some `SUPPRESSED`, some `NEW` on the *same* control) → partial match — usually a
  **tag-value or prefix** difference between resources (see §2).

---

## 2 — The prefix/tag mismatch (why rules silently don't fire)

**Root cause.** `{{ AcceleratorPrefix }}` in the config is a *replacement variable*
(`replacements-config.yaml`, e.g. `acme`). It is **not** guaranteed to equal the prefix the
LZA **framework** was installed with. If the installer used the **default `AWSAccelerator`**
prefix, then the real resources — lambdas, `AWSAcceleratorFailedAlarm`, `AWSAccelerator-LoggingStack`,
`AWSAccelerator-PrepareStack`, the `aws-accelerator-*` buckets, and the **`Accelerator` resource
tag** — all carry `AWSAccelerator`, while any rule matching `{{ AcceleratorPrefix }}` looks for
`acme` and matches nothing.

**Detect it.** Compare the deployed automation-rule names against a real resource ARN:

```bash
# Rule names render the config prefix (e.g. "acme-Lambda-VPC-Suppress"):
aws securityhub list-automation-rules --region <HomeRegion> \
  --query 'AutomationRulesMetadata[].RuleName' --output text
# vs. an actual LZA resource — note the prefix in the ARN / Accelerator tag:
aws securityhub get-findings --region <HomeRegion> \
  --filters '{"ComplianceSecurityControlId":[{"Value":"Lambda.3","Comparison":"EQUALS"}]}' \
  --query 'Findings[0].{Id:Resources[0].Id,Accel:Resources[0].Tags.Accelerator}' --output json
```

If rule names say `acme-…` but ARNs say `AWSAccelerator-…`, you have the mismatch.

**Two more gotchas the same investigation reveals:**

- **Finding-level tags are often `null`.** Security Hub doesn't always copy a resource's tags
  onto the finding (seen on Step Functions, S3). A rule keyed on `ResourceTags` will then miss
  even a correctly-tagged resource — **prefer matching `ResourceId` (the ARN)**.
- **Inconsistent `Accelerator` tag values.** Some buckets are tagged `acme`, some
  `AWSAccelerator`, some untagged. Tag-gated S3 rules catch only a subset.

**Fix (in `security-config.yaml`):**

1. For framework-resource rules, match **both** prefixes — values within one criteria key are
   OR'd:
   ```yaml
   - key: "ResourceId"
     filter:
       - value: "{{ AcceleratorPrefix }}"      # acme
         comparison: "CONTAINS"
       - value: "AWSAccelerator"               # actual framework prefix
         comparison: "CONTAINS"
   ```
   Do the same for the `Accelerator` tag (`{{ AcceleratorPrefix }}` **and** `AWSAccelerator`).
2. For S3 rules where the `Accelerator` tag is inconsistent/missing, **drop the tag filter**
   and match on the LZA bucket-name strings alone (`aws-accelerator-*`, `cdk-accel-assets`) —
   those names are specific enough to scope safely.
3. Do **not** "fix" this by changing the `AcceleratorPrefix` replacement to `AWSAccelerator`
   (renames BackupVault, CUR, budgets, the rules themselves) or by reinstalling with a custom
   prefix (recreates every framework stack). Correct the rule criteria instead.

---

## 3 — Classify a finding: is it accelerator-created?

Before suppressing, prove the resource is LZA-owned:

```bash
# Step Functions example — inspect the resource's real tags (NOT the finding's tags):
aws stepfunctions list-tags-for-resource --resource-arn <arn> --region <HomeRegion>
```

LZA-owned signals: `aws:cloudformation:stack-name` starting `AWSAccelerator-…`,
`nsf:managed-by = lza`, `Accelerator` tag present. If it's LZA framework plumbing → **suppress**
(§4). If it's a customer/manual resource (no LZA tags, generic name) → **fix or risk-accept**
(don't hide it).

---

## 4 — Suppress LZA-created findings

Add automation rules under `centralSecurityServices.securityHub.automationRules`. House pattern:
`ResourceType` + `ComplianceSecurityControlId` + a **scoping** filter (ARN substring; tag only if
the finding actually carries it). Examples this skill has shipped:

| Control | What it is | Scope | Why suppress |
|---|---|---|---|
| StepFunctions.1 | State machine logging off | `ResourceId ~ CreateOrganizationAccounts`, type `AwsStepFunctionsStateMachine` | LZA CDK provider-framework waiter (AWSAccelerator-PrepareStack); transient plumbing |
| CloudWatch.15 | Alarm has no action | `ResourceId ~ *FailedAlarm` | LZA pipeline failure alarm by design |
| Lambda.3 / Lambda.7 | Not in VPC / no X-Ray | LZA lambdas (both prefixes) | LZA control-plane lambdas |
| Kinesis.3, DynamoDB.4/6, KMS.1/2 | various | LZA `*-LoggingStack` / `*-PrepareStack` / installer (both prefixes) | LZA-managed lifecycle |
| S3.6/7/9/11/15/17/20 | bucket hardening | `aws-accelerator-*`, `cdk-accel-assets` (name only) | LZA/CDK buckets |

**Documented exceptions** (real risk, accepted with a compensating control — keep on the register):

| Control | Scope | Compensating control |
|---|---|---|
| IAM.21 | `policy/<Customer>-*` permission-set policies (service wildcards) | PermissionsBoundary on every write-access permission set |
| IAM.22 | break-glass IAM users (dormant by design, SEC03-BP03) | quarterly drill + break-glass tamper SCP + activity alerts |
| Backup.1 | Management/Audit/LogArchive (no workloads) | org backup policy covers Infrastructure + Workloads (§7) |

> For **non-accelerator** findings (manual CloudTrail trails with log-validation off, IAM users
> without MFA, console-created `cf-templates-*` buckets, "no Network Firewall" in non-inspection
> accounts) — **do not suppress**. Record them as customer actions on the register (§8).

---

## 5 — CIS section-4 monitoring (CloudWatch metric filters + alarms)

CIS 4.1–4.15 require a CloudTrail → metric filter → alarm → SNS pipeline for sensitive events
(root usage, unauthorized API, IAM/CloudTrail/Config/Org changes, etc.). **Neither Control Tower
nor LZA creates these** — `cloudWatch.metricSets`/`alarmSets` ship empty, so every CIS scanner
flags 4.x.

```bash
# Confirm the gap — which log group, how many filters:
aws cloudtrail describe-trails --region <HomeRegion> \
  --query 'trailList[].{Name:Name,Org:IsOrganizationTrail,CW:CloudWatchLogsLogGroupArn}'
aws logs describe-metric-filters --region <HomeRegion> \
  --log-group-name <CT-log-group> --query 'length(metricFilters)'
```

**Option A — build the pipeline (recommended).** Fill `cloudWatch.metricSets` + `alarmSets` in
`security-config.yaml` with the 15 canonical CIS filters/alarms, deployed to the account/region
holding the org trail's CloudWatch log group (with Control Tower that's the **Management**
account / HomeRegion; member accounts have no local trail). Route alarms to the existing
`SecurityHigh` / `SecurityMedium` SNS topics via **`snsTopicName`** (`snsAlertLevel` is
deprecated). A ready-to-edit block is in `references/cis-cloudwatch-block.yaml`.

> ⚠️ The Control Tower log group name carries a deployment-specific suffix
> (`aws-controltower/CloudTrailLogs-xxxxx`) — paste the real name into `logGroupName`; don't
> templatise it. If CT is re-baselined, update it.

**Option B — disable the controls.** AWS-supported when you rely on a centralized org trail +
GuardDuty. Note these controls are frequently already `DISABLED` in Security Hub — in which case
the findings you see come from an **external scanner** (Prowler/custom), and only Option A clears
them. If you want native-SH PASS, the controls must be **enabled in the Management account only**
(enabling them in member accounts makes them all FAIL — no local trail).

```bash
aws securityhub batch-get-security-controls --region <HomeRegion> \
  --security-control-ids CloudWatch.1 --query 'SecurityControls[0].SecurityControlStatus'
```

---

## 6 — Enable Amazon Inspector org-wide

**LZA has no native Inspector support** (config feature request open) — this is an **operational
(click-ops) change**, so record it on the register as config drift. One script does it all:

```bash
scripts/enable_inspector_org.sh <MGMT_PROFILE> <AUDIT_ACCT_ID> <HomeRegion>
```

It: (1) sets the **delegated admin = Audit** from the management account; (2) enables Inspector
on Audit; (3) sets org `auto-enable` for EC2 + ECR + Lambda + Lambda-code (future accounts);
(4) **associates** existing member accounts (the step that's easy to miss — `enable` alone fails
`ACCESS_DENIED` until members are associated); (5) enables the management account (it
self-manages). Resolves Inspector.1/.2/.3/.4 once scans complete.

> 💰 Inspector is **billable per scanned resource**; Lambda-code scanning is the biggest driver.
> Drop `lambdaCode` from auto-enable if cost-sensitive.

---

## 7 — AWS Backup plan coverage (Backup.1 / DynamoDB.4)

LZA's `global-config.yaml backup.vaults` only creates **vaults**, not **plans**. Plans come from
an **AWS Organizations backup policy** wired in `organization-config.yaml backupPolicies`
referencing a JSON plan in `backup-policies/`.

```bash
# Is a plan deployed in a workload account?
aws backup list-backup-plans --region <HomeRegion> --query 'BackupPlansList[].BackupPlanName'
grep -n "backupPolicies" organization-config.yaml
```

- Best-practice plan **already wired** (Continuous/Hourly/Daily/Weekly/Monthly, VSS, lifecycle):
  confirm its `deploymentTargets` cover the right OUs. Findings in **Management/Audit/LogArchive**
  are by-design (no workloads) → suppress Backup.1 for those account ids, or extend coverage.
- **No plan wired:** add a `backupPolicies` entry pointing at `backup-policies/primary-backup-plan.json`
  with `deploymentTargets` = Infrastructure + Workloads. Requires the `BACKUP_POLICY` org policy
  type enabled and the `<Prefix>-Backup-Role` present in targets.

---

## 8 — Risk register (deliverable)

Produce a register capturing **every suppression (pre-existing + new), every documented
exception, operational changes (Inspector), and the non-accelerator findings handed back to the
customer.** Use `references/risk-register-template.md`.

> Decide with the customer whether the register lives **in the config repo** (auditable, versioned)
> or **outside it** (e.g. a parent dir) if they don't want it public. Default: keep it out of the
> public config repo unless asked.

---

## 9 — Apply, validate, and remember: rules are not retroactive

```bash
# Validate before commit (YAML + cross-refs; full schema check happens in the pipeline):
python3 -c "import yaml; yaml.safe_load(open('security-config.yaml')); print('YAML OK')"
```

Cross-check: every alarm's `metricName`/`namespace` matches a defined metric; `snsTopicName`s
exist in `global-config snsTopics`; `deploymentTargets` accounts exist in `accounts-config`;
automation-rule names are unique. Commit → pipeline deploys.

**Automation rules only act on findings created/updated *after* the rule exists.** Existing `NEW`
findings stay until Security Hub re-evaluates (~12–24h) or you bulk-flip them:

```bash
scripts/bulk_suppress.sh <HomeRegion> <ControlId> "<ResourceId-substring>"
```

---

## Bundled scripts (`scripts/`)

| Script | Purpose |
|---|---|
| `audit_suppressions.sh` | Per-control `SUPPRESSED`/`NEW`/`RESOLVED` counts from the Audit aggregator — shows which rules actually fire |
| `enable_inspector_org.sh` | Full Inspector org enablement: delegated admin + auto-enable + associate members + management |
| `bulk_suppress.sh` | `batch-update-findings` to flip existing `NEW` findings to `SUPPRESSED` for a control + ARN substring (automation rules aren't retroactive) |

`references/`: `cis-cloudwatch-block.yaml` (15 metric filters + 15 alarms, ready to paste),
`risk-register-template.md`.

> Scripts modify Security Hub / Inspector / Organizations state — read before running and use
> management/Audit-scoped credentials.

---

## When to re-invoke this skill

- After `/lza-validate` (or a CIS/Prowler scan) surfaces a wall of findings.
- When you add suppression rules and the findings don't clear (→ §2, the prefix trap).
- On a cadence, to re-audit suppression effectiveness and the risk register.

## Related skills

- `/lza-validate` — surfaces the findings (security-services delegated admin checks) that come here
- `/lza-troubleshoot` — for pipeline *failures* (this skill is for *findings*, not failures)
- `/lza-configure` — `security-config.yaml` / `organization-config.yaml` authoring conventions
- Add new controls/patterns to §4 and the references as you meet them in the field.
