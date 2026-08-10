---
name: lza-bootstrap
description: Use when first preparing an AWS Organization to host AWS Landing Zone Accelerator, after /lza-plan is signed off. Walks through Management account verification, AWS Organizations trusted-services audit, break-glass access setup, service quotas, the Control-Tower setup decision (we recommend standalone CT, not LZA-bootstrapped), IAM Identity Center strategy, the config-repository-source decision (CodeCommit is deprecated), and the LZA installer CloudFormation deployment plus its first pipeline run. Invoke once per AWS Organization, BEFORE any real config is deployed.
---

# `/lza-bootstrap` — First-time AWS Organization preparation

> **Validated against LZA version:** 1.15.0
> **Predecessor skill:** `/lza-plan` (must be complete and signed off)
> **Successor skill:** `/lza-configure`

## Purpose

Get the AWS Organization into a state where the LZA installer can run successfully, and then install it. This skill prevents the entire class of failures that otherwise surface later as cryptic Control Tower errors mid-pipeline. When it finishes you will have:

- a verified management account that meets every LZA prerequisite,
- a known-clean Organizations trusted-services state,
- a tested break-glass access path,
- (recommended) a **standalone AWS Control Tower landing zone** already healthy,
- the **installer CloudFormation stack** deployed,
- a **running `AWSAccelerator-Pipeline`** that has CDK-bootstrapped every account/region — still on LZA's default config.

What this skill does **not** do: write the customer YAML (`/lza-configure`) or run the pipeline against it (`/lza-deploy`). Bootstrap stops at "the machine is built, verified, and idling."

> **Mental model.** The installer stack creates a CodePipeline. Its first run pulls config from a repo, **CDK-bootstraps** all target accounts/regions, then deploys whatever config it finds. On a fresh install that's the LZA sample — so the first run builds plumbing without imposing your design yet. Your design lands in `/lza-configure` + `/lza-deploy`.

---

## How to use this skill

Work through the steps **in order**. This skill **performs actions on AWS**, so for each step:

1. State what you're about to do and which plan value it consumes.
2. Confirm the prerequisite is met, or do the thing.
3. **Verify** before moving on — bootstrap failures are far cheaper to catch now than mid-pipeline.

Steps 6, 7, 8 and 9 are decisions; the rest are checks and actions. Do not deploy the installer (Step 10) until everything above it is green.

> ⚠️ **Everything here happens in the management account, in the HomeRegion from the plan.** Confirm account and region before every console/CLI action. A bootstrap mistake in the wrong region is one of the hardest things to clean up.

---

## Step 0 — Pre-flight: confirm the plan

Do not start until:

- `<customer>-lza-plan.md` exists, all 8 decisions recorded, **customer + NBS sign-off present**.
- You can read these plan values (you'll use them throughout):
  - `AcceleratorPrefix` (Decision 1)
  - `HomeRegion`, `EnabledRegions`, opt-in flag (Decision 2)
  - Account list + emails (Decision 4) — especially Management, LogArchive, Audit
  - IDC starting state (Decision 6) — drives Steps 2, 7, 8

If the plan isn't signed off, **stop and return to `/lza-plan`.** Relitigating Decision 1 (prefix) after the installer's first run is effectively a teardown.

### AWS credential preflight (before any AWS command)

Every step below runs the AWS CLI against the **management account** in the **HomeRegion**. Wrong account/region or an expired SSO session is the #1 source of confusing failures — verify first:

```bash
aws sts get-caller-identity     # Account + ARN — who am I?
aws configure list              # active profile + region
```

Confirm against `<customer>-lza-plan.md`: **Account == Management account**, **Region == HomeRegion**.

Set credentials up yourself — **never store creds in the repo, prefer temporary SSO credentials over long-lived keys:**
```bash
aws configure sso --profile <customer>-mgmt    # one-time
aws sso login --profile <customer>-mgmt
export AWS_PROFILE=<customer>-mgmt AWS_REGION=<HomeRegion>
```

Bootstrap needs **admin in the management account** (it creates the org baseline, Control Tower, and the installer). If identity/region is wrong, fix it before Step 1.

---

## Step 1 — Management account verification

**What you're confirming:** the account that will own the org is clean and capable.

- [ ] **AWS Organizations enabled with _all features_** (not consolidated-billing only). LZA requires all-features.
- [ ] Account is **not already an LZA/CT target** from an abandoned attempt — no leftover `AWSAccelerator-*` or `AWSControlTower*` stacks. Clean first if present.
- [ ] **Billing / Cost Explorer enabled**, valid payment method (LZA budgets/cost reporting depend on it).
- [ ] **No prefix collision:** custom `AcceleratorPrefix` → confirm nothing already uses it; stock `AWSAccelerator` → confirm no stray `AWSAccelerator-*` resources.

**Reversibility:** ❌ Organizations all-features is one-way. ❌ A custom prefix locks after the installer's first run.

**Verify:** `aws organizations describe-organization` → `"FeatureSet": "ALL"`.

---

## Step 2 — AWS Organizations trusted-services audit

**Why this is its own step:** the nastiest LZA bootstrap failures come from *pre-existing* org-level trusted-service access — especially IAM Identity Center and Control Tower — that conflicts with what CT/LZA wants to set up. Auditing it now turns a mid-pipeline mystery into a five-minute pre-check.

Run:
```
aws organizations list-aws-service-access-for-organization
```

For each enabled principal, know what it implies:

| Trusted service principal | What it means for bootstrap |
|---|---|
| `sso.amazonaws.com` | **IAM Identity Center is already org-enabled.** CT will want to manage IDC — this is the classic IDC-takeover trap. Resolve via Step 8 *before* CT setup. |
| `controltower.amazonaws.com` | A Control Tower deployment exists or existed. Inventory it (Step 7) — adopt or clean, never ignore. |
| `cloudtrail.amazonaws.com`, `config.amazonaws.com`, `guardduty…`, `securityhub…` | Org-level security services already delegated. LZA expects to own these; pre-existing delegated admins in the *wrong* account cause Audit-stage drift. |
| `account.amazonaws.com`, `member.org.stacksets…` | Generally fine; note for completeness. |

**Reversibility:** ⚠️ Disabling org-level IDC trusted access after CT is built requires tearing CT down. Decide here, not later.

**Record on the plan (append):**
```
Trusted-services audit (<date>):
  IDC org-enabled: yes/no
  Control Tower present: yes/no — <adopt|clean>
  Delegated admins found: <service → account>
```

---

## Step 3 — Break-glass / fallback access path

**Set this up before any destructive operation.** If CT/IDC setup goes wrong, SSO can become the very thing that's broken — you must have a non-SSO way back in.

- [ ] **Root user**: MFA enabled, credentials sealed and stored per customer policy.
- [ ] A dedicated **IAM break-glass user** (separate from any SSO identity) with admin, **its own MFA**, and access keys stored securely offline.
- [ ] Confirm both can sign in **today**, before you touch IDC or CT.

This is the SEC03-BP03 break-glass user referenced in `/lza-plan` Decision 6. Without it, a botched IDC takeover (Step 8) can lock the whole team out.

**Verify:** perform a test login with the break-glass IAM user (and confirm root MFA prompts correctly), then re-seal.

---

## Step 4 — Service quotas

Raise these **before** the installer — approvals take hours to days, and the pipeline stalls on boring limits.

| Quota | Required | Why |
|---|---|---|
| **CodeBuild — concurrent builds, Linux/Large** | **≥ 3** | Pipeline runs parallel CodeBuild jobs; <3 deadlocks Deploy stages. #1 first-install failure. |
| **Organizations — OU count** | ≥ planned OU tree + headroom | Default ceiling is low for a full LZA tree. |
| **Organizations — SCP count / SCP size** | per guardrail design | Compliance-heavy customers hit SCP-per-target and document-size limits. |
| **Organizations — accounts in org** | ≥ planned count + headroom | — |
| **Account creation rate** | ~10/hour (hard, not raisable) | 15+ accounts at launch → plan a two-pass deploy (flagged in Decision 4). |
| **Service Catalog — portfolio principals** | per team size | CT account factory uses Service Catalog; low limits block account vending. |
| **KMS — keys per region** | default usually OK | LZA creates many; watch old/small accounts. |
| **VPC / EIP / NAT GW per region** | per CIDR plan | Perimeter/Network hit EIP and NAT limits early. |

**Verify:** in Service Quotas (HomeRegion), the CodeBuild Linux/Large concurrency increase shows **Applied**, not merely Requested.

---

## Step 5 — Shared-account emails (LogArchive & Audit)

- CT/LZA **creates** LogArchive and Audit (or you **invite** existing ones).
- Each email must be **globally unique across all of AWS** and a **real, monitored inbox**. The `aws-managers+<purpose>@<domain>` convention (Decision 4) works **only if the base inbox accepts plus-addressed mail** — some corporate mail systems strip `+` tags. Confirm with the customer.
- The **management account email** must also be reachable (root + budget alerts).

**Reversibility:** ❌ An email attached to an AWS account can never be reused, even after closure. Triple-check spelling.

**Verify:** test-mail all three addresses and confirm receipt before the installer runs.

---

## Step 6 — Region & opt-in groundwork

Consume Decision 2:
- Operate in **`HomeRegion`** for all of bootstrap.
- **Opt-in regions** (Cape Town, Bahrain, Jakarta, Hyderabad, Zurich, Hong Kong, UAE, …): **enable each in the management account now** (Account → Regions). LZA can't govern a region the management account hasn't opted into; propagation is slow, so do it early.
- **Global-services region**: CloudFront/IAM and some global resources resolve in `us-east-1` (commercial) / `us-gov-west-1` (GovCloud) regardless of HomeRegion — expect stacks there.

**Verify:** every region in `EnabledRegions` shows ENABLED in the management account.

---

## Step 7 — DECISION: Control Tower setup approach

**What it controls:** how the AWS Control Tower landing zone comes into existence.

| Approach | Recommendation |
|---|---|
| **Standalone CT setup first (RECOMMENDED)** | Set up the CT landing zone **yourself** (console/API), verify it's healthy, *then* point the installer at it with `ControlTowerEnabled: Yes`. **Why we recommend this:** it decouples CT's lifecycle from the pipeline. CT setup failures are diagnosed in isolation against a clean baseline, not buried inside a multi-hour pipeline run — and the pipeline simply adopts a known-good landing zone. |
| **Let LZA bootstrap CT** | LZA 1.6.0+ *can* deploy the CT landing zone via the `landingZone` block in `global-config.yaml`. Convenient, but couples CT creation to pipeline execution — when it breaks, you're untangling two systems at once. Reserve for repeatable, well-understood environments. |
| **Organizations-only (no CT)** | Only for GovCloud, CT-unavailable regions, or explicit customer refusal. LZA manages SCPs/baseline directly; more config burden later. `ControlTowerEnabled: No`. |

**If a CT landing zone already exists** (from Step 2's audit): inventory its logging account, retention, and governed regions, and make them match the plan — adopt a *matching* landing zone, or you fight drift forever.

**Reversibility:** ⚠️ CT ↔ Organizations-only switch after install = major rework. ⚠️ Changing CT home region / logging config later ≈ rebuild.

**Record on the plan (append):**
```
CT approach: standalone-first | lza-bootstrapped | organizations-only
CT landing zone: created-standalone | pre-existing-adopted | deployed-by-lza | n/a
```

---

## Step 8 — IAM Identity Center strategy

**What it controls:** where and how IDC lives — and whether you walk into the takeover trap from Step 2.

**Decide:**
- **Org-level vs account-level IDC:** for a governed landing zone you want **org-level** IDC (delegated administration to the Audit/management account per the plan). Account-level/standalone IDC instances must be reconciled or they collide with CT.
- **Regional placement:** the IDC instance is **region-bound**. Place it in the **HomeRegion**. Migrating an IDC instance between regions later = rebuild (Decision 6).
- **Takeover path (the trap):** if Step 2 showed IDC already org-enabled:
  - *Clean, no custom permission sets* → let CT adopt it.
  - *Active users / custom permission sets in non-CT regions* → **inventory permission sets + account assignments first**; you may need to recreate them after CT setup.
  - If a rebuild is needed, **disable IDC trusted access deliberately and in the right order** — this is exactly where a prior engagement broke. See `/lza-troubleshoot` for the trusted-services sequence.
- ⚠️ **Deleting a pre-existing IDC instance can break the next CT landing-zone setup (`AWSServiceRoleForSSO` race).** If Step 2 found an empty/account-level IDC instance and you delete it so CT can create the org instance, deletion may also remove the `AWSServiceRoleForSSO` service-linked role. When CT then sets up the landing zone it re-creates that SLR *and uses it within a few minutes* — IAM hasn't propagated it yet, so the landing-zone CREATE fails with: *"the assumed role, AWSServiceRoleForSSO, doesn't have permission to perform the operation 'unknown operation'."* The landing zone lands in **FAILED**. **Mitigations:** after deleting the old IDC instance, **pre-create the SLR** (`aws iam create-service-linked-role --aws-service-name sso.amazonaws.com`) and give it a few minutes before the pipeline runs CT setup; if the landing zone already failed this way, the SLR now exists — **`reset-landing-zone` and it succeeds** (see `/lza-troubleshoot` → "CT landing zone AWSServiceRoleForSSO race"). The failure is a one-time eventual-consistency race, not a config error.

**Do this with the break-glass path (Step 3) confirmed working** — an IDC misstep here can lock out SSO logins.

**Reversibility:** ⚠️ Disabling org-level IDC after CT exists → CT teardown/rebuild. ✅ Changing identity *source* (built-in → external IdP) is supported later.

**Record on the plan (append):**
```
IDC: org-level | account-level
  Region: <HomeRegion>
  Pre-existing instance: yes/no — <adopt|rebuild>
  Permission sets to recreate: <list or none>
```

---

## Step 9 — DECISION: configuration repository source

**What it controls:** where LZA reads its YAML config. The installer wires the pipeline to this; `/lza-configure` writes files into it.

> **CodeCommit is deprecated.** AWS no longer onboards new accounts to CodeCommit. Do **not** choose `codecommit` for a new engagement.

Installer parameter **`ConfigurationRepositoryLocation`**:

| Value | Use it when | Trade-offs |
|---|---|---|
| **`codeconnection` (recommended)** | Config in **GitHub/GitLab/Bitbucket**. | Real Git workflow, PRs, history. Needs an **AWS CodeConnections** connection (Step 9a) + ARN. Our default. |
| **`s3`** | No external Git; air-gapped / GovCloud-ish. | Config is `aws-accelerator-config.zip` in S3. No native PR review — re-zip and upload to change. Workable, clunky. |
| **`codecommit`** | ❌ Legacy/existing installs only. | Don't pick for new work. |

**Reversibility:** ✅ Migratable later (AWS documents CodeCommit/S3 → external-Git), but avoidable churn — pick right now.

### Step 9a — If `codeconnection`: create the connection (GitHub) — needs a GitHub org owner

A CodeConnection to a GitHub **organization** installs the **AWS Connector for GitHub** GitHub App into that org. **Installing an app on an org requires GitHub _organization owner_ permission** — so coordinate with the customer's GitHub org owner *before* you start, or you'll stall at a pending approval.

**AWS side (management account, HomeRegion):**
1. Developer Tools console → **Settings → Connections → Create connection**.
2. Provider **GitHub** → enter a connection name → **Connect to GitHub**.
3. Choose **Authorize AWS Connector for GitHub** (OAuth handshake).
4. Under **GitHub Apps**, choose **Install a new app**.

**GitHub side (the org owner does this, or approves it):**
5. On **Install AWS Connector for GitHub**, select the **organization** that owns the config repo (not a personal account).
6. Choose repository access — **Only select repositories → the config repo** (least privilege; don't grant "All repositories"), leave other defaults → **Install**.
7. **Permission gate:** if the person clicking is **not** an org owner, GitHub does *not* install — it sends an **install request to the org owners**. An owner must open GitHub → **Org → Settings → Third-party Access / GitHub Apps → pending requests** and **approve** it (and confirm the selected repos). Until approved, the AWS connection stays **PENDING**.

**Back on AWS:**
8. After install/approval, the installation ID appears under GitHub Apps → **Connect**. Confirm status **AVAILABLE** (not Pending).
9. Copy the **Connection ARN** → installer `CodeConnectionArn`.
10. Create the **empty config repo** (e.g. `<customer>-lza-config`) in that org with the target branch (commonly `main`). `/lza-configure` populates it.

> **Notes:** one AWS Connector app maps **1:1 to a GitHub org** — a separate connection per org. The connection grants AWS access to the selected repos; rotating/removing it is done from both the GitHub App settings and AWS Connections. GitLab/Bitbucket follow the same pattern with their own connector.

**Record on the plan (append):**
```
Config source: codeconnection | s3
  CodeConnection ARN: <arn>     (codeconnection)
  GitHub org / repo / branch: <org>/<name> @ <branch>
  AWS Connector for GitHub installed + approved by org owner: yes/no (<owner name>)
  S3 config bucket: <name>      (s3)
```

### Step 9b — GitHub token in Secrets Manager (ONLY if installer source = GitHub)

This is a **separate** GitHub touchpoint from Step 9a. It applies **only if you set the installer's `RepositorySource: github`** — i.e. you pull the LZA **engine source code** from a GitHub fork instead of the AWS-managed S3 template. The standard "launch from the AWS Solutions page" install does **not** need this; skip Step 9b in that case.

If you do use `RepositorySource: github`, the installer authenticates to GitHub with a **personal access token (PAT) stored in Secrets Manager** — create it *before* deploying:

1. **GitHub:** create a **Personal Access Token (Classic)** with scope **`public_repo`** (enough to read the public LZA source). Set a sensible expiry and calendar a rotation reminder.
2. **AWS Secrets Manager (management account, HomeRegion):** Store a new secret → **Other type of secret → Plaintext** → paste the token **with no quotes/leading/trailing spaces** (delete the example JSON entirely).
3. Secret name **exactly** `accelerator/github-token` (case-sensitive).
4. **Disable rotation.**

> ⚠️ **Token expiry breaks the pipeline.** When the PAT expires, the Source stage fails to pull the engine source. Rotate the secret value before expiry (and note CloudTrail must be enabled for the token-rotation automation to function). Storing it anywhere other than `accelerator/github-token` in the HomeRegion = installer can't find it.

**Record on the plan (append):**
```
Installer source: s3-solution-template | github (RepositorySource=github)
  GitHub PAT in Secrets Manager (accelerator/github-token): yes/no
  PAT expiry / rotation owner: <date> / <name>
```

---

## Step 10 — Deploy the installer stack

**Template:** `AWSAccelerator-InstallerStack.template` (the *Landing Zone Accelerator on AWS* Solution — launch via the Solutions page or the **1.15.0** GitHub release artifact). Deploy in the **management account, HomeRegion**.

Map each parameter from the plan:

| Parameter | Value |
|---|---|
| `AcceleratorPrefix` | Decision 1 prefix — **must be byte-for-byte identical to `replacements-config.yaml`'s `AcceleratorPrefix`** (see below) |
| `ManagementAccountEmail` / `LogArchiveAccountEmail` / `AuditAccountEmail` | Decision 4 emails |
| `ControlTowerEnabled` | `Yes`/`No` from Step 7 |
| `ConfigurationRepositoryLocation` | `codeconnection`/`s3` from Step 9 |
| `UseExistingConfigRepo` | `Yes` if you pre-created repo/bucket, else `No` |
| `ExistingConfigRepositoryName` / `...BranchName` | repo + branch (if existing) |
| `CodeConnectionArn` / `ConfigurationRepositoryOwner` | from Step 9a (codeconnection) |
| `EnableApprovalStage` | `Yes` (manual gate before Deploy — recommended) |
| `ApprovalStageNotifyEmailList` | engineer/customer notification emails |
| `AcceleratorQualifier` | only for multiple LZA instances in one account (rare) |

> 🚨 **Prefix must match the config — the #1 silent-mismatch trap.** The `AcceleratorPrefix` you enter here is the **same** prefix `/lza-configure` puts in `replacements-config.yaml` (`{{ AcceleratorPrefix }}`). They are two halves of one setting: the installer/pipeline builds and looks up resources under this name, and the config names resources under the config value. If they differ (e.g. installer left at default `AWSAccelerator` but config set to `acme`, or a typo/case difference), the pipeline references names that don't exist and fails. **Enter the exact same string in both places.** Both lock after the first run. (The prefix names LZA-managed *infra* — roles, KMS keys, S3 buckets, CFN stacks, SCPs, SNS, Lambdas. It does **not** rename VPC/subnet `name:` tags, and the CDK qualifier `cdk-accel-*` is independent of it.) If you choose a non-default prefix, also have `/lza-configure` replace the baseline's hardcoded `"AWSAccelerator"` in the `security-config.yaml` Security Hub suppression rules with `{{ AcceleratorPrefix }}`, or those suppressions won't match.

**Watch for:** the stack creates **two pipelines** — `AWSAccelerator-Installer` (builds the toolkit), which then triggers `AWSAccelerator-Pipeline` (the real one). Email/prefix typos here are as irreversible as in the plan — re-read before "Create stack."

**Verify:** installer stack reaches `CREATE_COMPLETE` and `AWSAccelerator-Installer` starts on its own.

---

## Step 11 — First pipeline run (the CDK bootstrap)

`AWSAccelerator-Pipeline` first-run stages (1.15.0), in order:

1. **Source** — pulls config from your repo/bucket.
2. **Build** — synthesizes CDK.
3. **Prepare** — org scaffolding, config validation.
4. **Accounts** — creates/invites accounts. *Subject to the ~10/hour limit.*
5. **Bootstrap** — **CDK-bootstraps every target account × every EnabledRegion.** Slow, most quota-sensitive — this is what makes the env deployable.
6. **Deploy** (Key → Logging → Organizations → SecurityAudit → Network → …) — applies whatever config is present (the LZA sample, on a fresh install).

**Expect 1–3+ hours**, dominated by Accounts + Bootstrap. With `EnableApprovalStage: Yes` it pauses at the manual gate — intended.

**Common first-run failures (all surfaced here, all cheap now):**
- CodeBuild concurrency <3 → deadlock (Step 4).
- Opt-in region not enabled in mgmt account → bootstrap fails for it (Step 6).
- Bad shared-account email → Accounts stage fails (Step 5).
- Pre-existing CT/IDC mismatch → Organizations/SecurityAudit drift (Steps 2, 7, 8).

Anything else → `/lza-troubleshoot`.

---

## Step 12 — Verify bootstrap is complete

- [ ] `AWSAccelerator-Pipeline` last run **Succeeded** (or paused cleanly at the approval gate after Bootstrap).
- [ ] **CDKToolkit** stack present in **every** target account × every `EnabledRegion`. Spot-check management, LogArchive, Audit, and one workload account.
- [ ] LogArchive and Audit **exist and sit in the Security OU**.
- [ ] CT path: landing zone **healthy / no drift**.
- [ ] IDC reachable; break-glass path still works (Step 3).
- [ ] Config repo/bucket reachable; pipeline reads from it.

**Record on the plan (append):**
```
Bootstrap completed: <date> by <engineer>
LZA version installed: 1.15.0
Pipeline: AWSAccelerator-Pipeline — first run <succeeded|paused-at-approval>
CDK bootstrap verified in: <N accounts × M regions>
```

---

## When to re-invoke this skill

- New customer → fresh `/lza-bootstrap` after `/lza-plan`.
- **Adding a new EnabledRegion** → it needs CDK bootstrap; re-run Steps 6, 11–12 for that region rather than the whole skill.
- Migrating the config source → Step 9 only.
- **Never** re-run to "change the prefix" — that's a rebuild, not a bootstrap.

## Related skills

- Before this: `/lza-plan` — the signed-off plan this skill consumes
- After this: `/lza-configure` — write the real YAML into the config repo
- Then: `/lza-deploy` — run the pipeline against that YAML
- After deploy: `/lza-validate`, `/lza-add-account`
- Anytime trouble (esp. IDC/Control Tower traps): `/lza-troubleshoot`
