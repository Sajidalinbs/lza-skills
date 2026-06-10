---
name: lza-deploy
description: Use when running the LZA pipeline end-to-end after the configs are in place. Explains every pipeline stage, expected duration, what success looks like at each stage, what "stuck vs failing" means, and how to safely restart or recover. Invoke when triggering the pipeline or while watching a run.
---

# `/lza-deploy` — Running the LZA pipeline end-to-end

> **Validated against LZA version:** 1.15.0
> **Predecessor skill:** `/lza-configure`
> **Successor skill:** `/lza-validate`

## Purpose

Demystify the `AWSAccelerator-Pipeline`. Each stage has its own purpose, IAM principals, typical failure modes, and recovery patterns. Knowing what's normal prevents over-reacting to long-running stages and helps you spot real problems early.

## How to use this skill

1. Confirm the config files are committed to the config repo (`/lza-configure` done).
2. Trigger the pipeline (push to the configured branch, or `start-pipeline-execution`).
3. Watch it stage by stage against the map below. **Do not intervene on a long-running stage** unless it crosses the "stuck" thresholds.
4. On any failure → jump straight to `/lza-troubleshoot` with the failing stage name.

> **Trigger:** a commit to the config repo branch auto-starts the pipeline. To trigger manually:
> `aws codepipeline start-pipeline-execution --name AWSAccelerator-Pipeline`

---

## Step 0 — AWS credential preflight (before any AWS command)

This skill runs the AWS CLI against the **management account** in the **HomeRegion**. Wrong account/region or an expired SSO session is the #1 source of confusing failures — verify first:

```bash
aws sts get-caller-identity     # Account + ARN — who am I?
aws configure list              # active profile + region
```

Confirm against `<customer>-lza-plan.md`: **Account == Management account**, **Region == HomeRegion**.

Set credentials up yourself — **never store creds in the repo, prefer temporary SSO credentials over long-lived keys:**
```bash
aws sso login --profile <customer>-mgmt
export AWS_PROFILE=<customer>-mgmt AWS_REGION=<HomeRegion>
```

Deploy/monitor needs access to **CodePipeline, CodeBuild, CloudFormation, and Control Tower** in the management account. If identity/region is wrong, fix it before triggering or inspecting the pipeline.

---

## Pipeline stage map (`AWSAccelerator-Pipeline`)

| Stage | What runs | Typical duration | Common failures |
|---|---|---|---|
| **Source** | Pull config repo (CodeConnections / S3 / CodeCommit) | <1 min | Repo permissions, missing branch, broken CodeConnection |
| **Prepare** | Validate configs, generate CDK assets | 2–5 min | Config schema errors, missing required fields |
| **Accounts** | Create accounts via Organizations, enroll in CT, baseline OUs | 10–30 min | CT pre-check failures, quarantine-SCP deny (see `/lza-troubleshoot`) |
| **Bootstrap** | CDK-bootstrap each managed account × region | 5–15 min | StackSet permission issues, region restrictions, opt-in not enabled |
| **Review** | Manual approval gate (if `EnableApprovalStage: Yes`) | varies (human) | n/a — intended pause |
| **Logging** | Central S3, CloudWatch destinations, KMS | 5–10 min | KMS key policy, bucket name conflicts |
| **Organization** | Apply SCPs / RCPs / tag policies / backup policies to OUs | 3–8 min | SCP content errors, attachment quota (max 5/target) |
| **SecurityAudit** | Security Hub, GuardDuty, Macie delegated admin + standards | 5–15 min | Service-linked role creation, region-specific gaps |
| **Deploy** | Network (TGW/VPC/NFW), security resources, customizations | 20–45 min | CIDR conflicts, NFW Suricata syntax, custom CFN errors |
| **Finalize** | Release quarantine SCPs, mark accounts complete | 1–3 min | rare |

> **Whole first run: budget 1.5–3.5 hours**, dominated by Accounts + Deploy. Subsequent runs (config tweaks) are much faster because accounts already exist and bootstrap is cached.

---

## What success looks like

- [ ] All stages **green** in `aws codepipeline get-pipeline-state --name AWSAccelerator-Pipeline`
- [ ] **No drift** in any enabled baseline: `aws controltower list-enabled-baselines` → all `SUCCEEDED`
- [ ] All accounts show `EnabledControls` `SUCCEEDED` for every enabled control
- [ ] **No quarantine SCP** attached to any account after Finalize (the signal LZA finished cleanly)

If all four hold, move to `/lza-validate` for the hands-on proof.

---

## Stuck vs failing — how to tell

A long stage is not a failed stage. Calibrate before you touch anything:

- **Long-running ≠ stuck.** The Accounts stage normally takes 10–30 min; Deploy 20–45 min. This is expected.
- **CT baseline operations have a ~30-min internal timeout** — a baseline op can legitimately sit for half an hour.
- **Real hang threshold:** a single stage stuck **> 90 min** with no CodeBuild log progress is almost always a genuine hang.
- **How to inspect what a stage is actually doing:** CodeBuild → the project for that stage → most recent log group → latest stream. The live log tells you whether it's working or wedged.

```bash
# Where is it, and is it moving?
aws codepipeline get-pipeline-state --name AWSAccelerator-Pipeline \
  --query 'stageStates[].{stage:stageName,status:latestExecution.status}' --output table
# CT baseline progress
aws controltower list-enabled-baselines
```

---

## Restart and recovery

- **Re-trigger:** `aws codepipeline start-pipeline-execution --name AWSAccelerator-Pipeline`. Most stages are **idempotent** — re-running after a fix is safe and the normal recovery path.
- **No-op commit:** pushing an empty/trivial commit to the config branch auto-triggers a fresh run (handy after fixing a deployed-resource issue outside the repo).
- **Skip flags** (`SkipEnrollAccounts`, `SkipManageAccountsAlias`, etc.): powerful and dangerous — **only use with AWS Support guidance**. They mask stages rather than fix them.
- **Manual approval:** if paused at Review, approve in the CodePipeline console once you've eyeballed the change set.
- **After fixing an SCP/CT problem:** see `/lza-troubleshoot` — note that the enroll-accounts module **re-attaches** the quarantine SCP at the start of Accounts, so you must fix SCP *content* with `update-policy`, not just detach.

---

## Monitoring during a run

```bash
aws codepipeline get-pipeline-state --name AWSAccelerator-Pipeline   # stage status
aws controltower list-enabled-baselines                              # CT health
```
- Console: **CodePipeline → AWSAccelerator-Pipeline → visualize** for the live graph.
- **CloudWatch dashboards**: LZA installs some — useful for at-a-glance health during long runs.

---

## Cost during deployment (starts billing the moment Deploy runs)

Once the **Deploy** stage provisions the network, real money starts:

| Resource | Cost | Notes |
|---|---|---|
| CodeBuild minutes | per-minute | small but non-zero across many builds |
| **NAT Gateways** (3 in egress VPC) | ~$32/mo each + data | live as soon as deployed |
| **Network Firewall endpoints** (per AZ in inspection VPC) | ~$0.395/hr each + data | the biggest fixed cost; 3 AZs ≈ $850/mo before traffic |
| Config recorders, GuardDuty, Security Hub | per-region baseline | ~$100–300/mo/region (flagged in Plan Decision 2) |

Tell the customer the meter starts at Deploy, not at go-live. For non-prod, consider fewer AZs / disabling NFW until needed.

---

## When to re-invoke this skill

- Every config change → re-trigger and watch the relevant stages (config-only changes skip Accounts/Bootstrap quickly).
- After a `/lza-troubleshoot` fix → re-run to confirm the stage goes green.
- Adding accounts → `/lza-add-account` drives the run, but the stage map here still applies.

## Related skills

- Before: `/lza-configure` — the YAML this pipeline consumes
- After: `/lza-validate` — prove the green pipeline actually works
- On any failure: `/lza-troubleshoot` — diagnostic playbook keyed by stage
- Day-2: `/lza-add-account`
