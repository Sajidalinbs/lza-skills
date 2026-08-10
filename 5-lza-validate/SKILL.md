---
name: lza-validate
description: Use after a successful LZA pipeline run to verify the deployment is healthy. Covers Control Tower enrollment status, SCP/RCP/tag-policy attachment audit, security-services delegated admin verification, TGW sharing and routing, central logging pipeline, AWS Config aggregator, and hands-on network connectivity tests. Invoke immediately after the pipeline reaches Finalize, and again on a cadence (weekly/monthly).
---

# `/lza-validate` — Post-deployment validation

> **Validated against LZA version:** 1.15.0
> **Predecessor skill:** `/lza-deploy`
> **Successor skill:** `/lza-add-account` (for day-2 work)

## Purpose

"Pipeline went green" doesn't mean "deployment is correct." A successful run proves the *config applied*; it does not prove the landing zone is *doing what it should*. This skill walks the practitioner through hands-on checks that prove it — control health, policy attachment, security coverage, real network paths, and central logging.

## How to use this skill

Run the read-only audits first (Control Tower → policies → security → network → logging → IDC), fix anything red via `/lza-troubleshoot`, then do the **hands-on tests** — those are the ones that catch silent gaps the APIs report as "fine." Finish by producing the customer-facing report.

> Run from the **management account** for org/CT queries, and assume into **Audit** for security-service aggregation. Many "missing" results are just the wrong account/region or per-account-vs-aggregator confusion (see `/lza-troubleshoot`).

---

## Step 0 — AWS credential preflight (before any AWS command)

This skill runs the AWS CLI against the **management account** (and assumes into **Audit**) in the **HomeRegion**. Wrong account/region or an expired SSO session is the #1 source of confusing "missing resource" results — verify first:

```bash
aws sts get-caller-identity     # Account + ARN — who am I?
aws configure list              # active profile + region
```

Confirm against `<customer>-lza-plan.md`: **Account == Management account**, **Region == HomeRegion**.

```bash
aws sso login --profile <customer>-mgmt
export AWS_PROFILE=<customer>-mgmt AWS_REGION=<HomeRegion>
```

Validation is read-only — **use a ReadOnlyAccess-style profile so a validation pass can't change anything** (safest). Never store creds in the repo; prefer temporary SSO credentials.

---

## 1 — Control Tower health

```bash
aws controltower get-landing-zone --landing-zone-identifier <id>
aws controltower list-enabled-baselines
aws controltower list-enabled-controls --target-identifier <ou-arn>
```

- [ ] `get-landing-zone` → `status: ACTIVE`, **`driftStatus: IN_SYNC`**
- [ ] `list-enabled-baselines` → all `SUCCEEDED`, **none `FAILED`**
- [ ] `list-enabled-controls` count matches the expected guardrail set
- [ ] Each account shows enrolled (CT console → Accounts, or per-account enrollment status)

Drift here is the first thing to fix — everything downstream assumes a healthy CT.

---

## 2 — SCP attachment audit

For every customer-managed SCP, confirm it's attached where it should be and **nowhere it shouldn't**:

```bash
aws organizations list-policies --filter SERVICE_CONTROL_POLICY
aws organizations list-policies-for-target --target-id <ou-or-account-id> \
  --filter SERVICE_CONTROL_POLICY        # per-target = ground truth
```

- [ ] **Quarantine SCP is NOT attached to any account** post-Finalize (its presence means LZA didn't finish — see `/lza-troubleshoot`)
- [ ] `Workloads/*` OUs carry the expected guardrails (Core-Guardrails-1/2, Workloads-Guardrails)
- [ ] `Suspended` OU carries `Suspended-Guardrails`
- [ ] CT-managed `aws-guardrails-*` SCPs are present
- [ ] **Use the per-target view** (`list-policies-for-target`), not `list-targets-for-policy` — the per-policy view lags due to eventual consistency (see `/lza-troubleshoot`)

---

## 3 — Tag policies

- [ ] Org tag policy attached at the expected scope
- [ ] `nsf` tag policy attached (if used)
- [ ] Compliance status: **Resource Groups → Tag Policies → Compliance** shows resources reporting (and, if `enforced_for` is on, no unexpected blocks)

---

## 4 — Backup policies

```bash
aws organizations list-policies --filter BACKUP_POLICY
```

- [ ] Backup policy attached to **Infrastructure + Workloads** OUs
- [ ] AWS Backup **vault present in each in-scope account**
- [ ] Vault Lock mode is what the plan intended (governance vs the irreversible compliance mode)

---

## 5 — Security services (delegated admin = Audit)

- [ ] **GuardDuty**: delegated admin = Audit, all member accounts enrolled
- [ ] **Security Hub**: delegated admin = Audit, standards enabled (AWS FSBP, CIS, + PCI DSS if in scope)
- [ ] **Macie**: delegated admin = Audit, member accounts associated
- [ ] **AWS Config**: org-wide **aggregator in Audit** — query via the aggregator, not per-account (see pitfall below)
- [ ] **Detective / Inspector**: enabled if the plan called for them

> **Pitfall:** querying AWS Config from the Audit account with `select-resource-config` returns **only Audit's own recorder**. To see the whole org you must use **`select-aggregate-resource-config`** against the aggregator (or Console → Config → Aggregators → Advanced query). This trips everyone once — it's in `/lza-troubleshoot`.

---

## 6 — Network connectivity

- [ ] **TGW shares** the correct OUs (`Infrastructure` + `Workloads/*`) — if an OU is missing from `shareTargets`, its VPCs get a TGW attachment with **no peer route**
- [ ] TGW **attachments** exist in all expected VPCs
- [ ] **Route table associations** match design: workload VPCs → `rt-spoke`, inspection → `rt-firewall`
- [ ] **Network Firewall endpoints healthy in all 3 AZs**
- [ ] **NAT Gateways** present in each AZ of the egress VPC
- [ ] **Per-VPC interface endpoints** provisioned where designed (or central endpoints VPC reachable)

---

## 7 — Central logging

- [ ] `aws-accelerator-central-logs-*` bucket exists in **LogArchive**
- [ ] **CloudTrail org trail** present and actively writing
- [ ] **VPC Flow Logs** reaching the central log bucket
- [ ] **NFW alert/flow logs** reaching the central log bucket
- [ ] **Dynamic log partitioning** patterns match the deployed log-group names (cross-check `security-config.yaml` + `dynamic-partitioning/log-filters.json`) — mismatched names = logs land unpartitioned

---

## 8 — IAM Identity Center

- [ ] Permission sets exist (Admin, ReadOnly, Developer, Auditor… per plan)
- [ ] Account assignments distributed to the right accounts/groups
- [ ] SSO portal URL reachable and login works

---

## 9 — Hands-on tests (the ones that catch silent gaps)

APIs can say "healthy" while the data path is broken. Prove the paths:

1. **Interface endpoints work:** SSO into a workload account, launch an EC2 in a **private subnet**, confirm **SSM Session Manager** connects (no public IP, no bastion).
2. **Egress path works:** from that EC2, `curl https://google.com` should succeed — proving traffic flows through the inspection VPC (NFW) and out via NAT.
3. **East-west TGW routing works:** from a **Prod** EC2, reach a **SharedServices** internal IP — proving inter-VPC routing over the TGW.
4. **Security aggregation works:** in the **Audit** account, `aws securithub get-findings` returns findings **from member accounts**, not just Audit.

### Automated ingress + egress proof through the NFW (Terraform harness) ⭐

The single most thorough network check — proves the **full cross-account, cross-VPC, cross-firewall** data path in one apply, instead of hand-launching EC2s. A bundled, parameterized Terraform stack ships in **[`test-infra/`](./test-infra/README.md)**.

```bash
cd test-infra
cp terraform.tfvars.example terraform.tfvars   # set prefix, region, profiles, workload VPC/subnet names
terraform init && terraform apply              # ~19 resources, ~$1.50/day, throwaway
# INGRESS:
curl -s http://$(terraform output -raw public_alb_dns_name)/ | head   # expect "Welcome to nginx!"
# EGRESS:
aws logs tail "$(terraform output -raw ecs_log_group)" --log-stream-name-prefix egress --since 5m --profile <stg> --region <region>
terraform destroy                              # always tear down after
```

It stands up a public ALB (Perimeter) → cross-account 443 IP target → TGW → **NFW** → internal ALB (workload) → ECS nginx, plus an ECS egress-probe sidecar. **Green = `HTTP 200` nginx HTML (ingress) + the probe reaching AWS (egress).**

- **Prereq:** the inspection layer must actually be deployed (TGW `rt-spoke→inspection` / `rt-firewall→egress`, NFW `READY`, NAT, `ingress→IGW`) — confirm §6 first, or the harness fails at the routing layer (not a harness bug).
- **Confirm the tag:Name values first** — LZA names subnets `subnet-<tier>-<az>` (not `<prefix>-<tier>-<az>`); set them in `terraform.tfvars`.
- Under an **allow-all** firewall the egress probe's `example.com` line returns `HTTP 200`; under a tightened per-SNI allowlist it's denied — both are correct for the current ruleset.

Any failure here points back to a specific config block — chase it via `/lza-troubleshoot`.

---

## 10 — Validation report (deliverable)

Produce a customer-facing report capturing every green check above, dated, with the LZA version. Suggested structure:

```markdown
# <Customer> LZA Validation Report — <date>
LZA version: 1.15.0   |   Validated by: <engineer>

## Control Tower      ✅ ACTIVE / IN_SYNC
## SCP / tag / backup ✅ attached as designed, quarantine released
## Security services  ✅ delegated to Audit, all members enrolled
## Network            ✅ TGW shares, NFW healthy, egress + east-west verified
## Central logging    ✅ CloudTrail + flow + NFW logs landing in LogArchive
## IAM Identity Center✅ permission sets + assignments + portal
## Hands-on tests     ✅ SSM / egress / east-west / SecurityHub aggregation
## Exceptions / follow-ups: <list>
```

---

## When to re-invoke this skill

- Immediately after every pipeline run that changes baseline/network/security.
- On a **cadence** (weekly/monthly) to catch drift — especially CT `driftStatus`.
- After `/lza-add-account` — validate just the new account's slice.

## Related skills

- Before: `/lza-deploy` — produces the green run this skill scrutinizes
- After: `/lza-add-account` — day-2 growth
- On any red check: `/lza-troubleshoot`
