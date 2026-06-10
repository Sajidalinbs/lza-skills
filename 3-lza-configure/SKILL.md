---
name: lza-configure
description: Use when filling in the LZA configuration YAML files for a customer engagement. Walks through every config file (replacements-config, accounts-config, organization-config, global-config, security-config, network-config, iam-config, customizations-config) with concrete examples and the pitfalls per file. Invoke after `/lza-plan` and `/lza-bootstrap` are complete.
---

# `/lza-configure` — Filling in the LZA YAML config files

> **Validated against LZA version:** 1.15.0
> **Predecessor skill:** `/lza-bootstrap`
> **Successor skill:** `/lza-deploy`

## Purpose

A walkthrough of every LZA config file: what it does, what to put in it, and the most common ways it goes wrong. Every value here should already be decided in `<customer>-lza-plan.md` — this skill is about **translating the plan into valid YAML**, not making new decisions. If you find yourself making a design choice here, stop and go back to `/lza-plan`.

## Step 0 — Start from the AWS baseline (don't write from scratch)

AWS ships a ready, opinionated baseline — the **LZA Universal Configuration** (`aws/lza-universal-configuration`, formerly the `reference/sample-configurations` folder). Its `modules/base/default` contains all six YAML files **plus** the supporting policy folders (`service-control-policies/`, `rcp-policies/`, `declarative-policies/`, `tagging-policies/`, `backup-policies/`, `dynamic-partitioning/`, `ssm-documents/`, …) already wired with `{{ AcceleratorPrefix }}` replacements, a Quarantine SCP, Core-Guardrails SCPs/RCPs, and the standard accounts/OUs.

**Seed the config repo first, then customize:**
```bash
intake/fetch_baseline.sh <config-repo-dir>          # copies base/default into the repo
```

What the baseline ships (so you customize, not author):
- **Accounts:** Management, LogArchive, Audit (mandatory) + Network, SharedServices, Perimeter
- **OUs:** Security, Infrastructure, Suspended (`ignore`), Workloads/{Sandbox,Dev,Test,Prod}
- **Prefix:** `AWSAccelerator` in `replacements-config.yaml` — change BEFORE first deploy

> **Networking is NOT taken from the baseline.** We do **not** use IPAM, and we do **not** deploy a DNS hub VPC or a central interface-endpoints VPC. The baseline's `modules/network/{hub-and-spoke,shared-vpc}` bundle all three — so seed **base only** and build `network-config.yaml` from the intake planner (explicit CIDRs). Where a spoke needs private AWS API access it gets its own small per-VPC `endpoints` tier instead of a shared endpoints VPC. If you copy a network module for reference, strip its IPAM / DNS-VPC / endpoints-VPC blocks.
>
> **AWS-native alternative:** the [LZA MCP Server](https://github.com/awslabs/lza-mcp-server) offers a "Guided UC Merge" to merge Universal Config interactively — complementary to these skills.

The sections below are then about **customizing each baseline file**, not creating it.

## How to use this skill

After Step 0, the config repo (`<customer>-lza-config`, created in `/lza-bootstrap` Step 9) holds these files. Customize them **in this order** — later files reference names defined in earlier ones:

1. `replacements-config.yaml` — variables everything else interpolates
2. `accounts-config.yaml` — the accounts
3. `organization-config.yaml` — the OU tree, SCPs, tag/backup policies
4. `global-config.yaml` — Control Tower, logging, budgets
5. `security-config.yaml` — security services, IDC, findings suppression
6. `network-config.yaml` — TGW, VPCs, firewall (the biggest, most error-prone file)
7. `iam-config.yaml` — federation, roles
8. `customizations-config.yaml` — custom CFN (only if needed)

After each file, **lint mentally against the plan**: does every name/email/CIDR match `<customer>-lza-plan.md`? A mismatch caught here is free; caught in the Deploy stage it's an hour.

> Reference the baseline at [aws/lza-universal-configuration](https://github.com/aws/lza-universal-configuration) and the engine at [awslabs/landing-zone-accelerator-on-aws](https://github.com/awslabs/landing-zone-accelerator-on-aws) for the exact schema of any block — this skill covers intent and pitfalls, not the full schema.

---

## 1 — `replacements-config.yaml`

**What it does:** defines `{{ variables }}` that every other config file can interpolate. Set it first so the rest of the configs stay DRY.

```yaml
globalReplacements:
  - key: AcceleratorPrefix
    type: String
    value: <prefix>                  # from Plan Decision 1 — see warning below
  - key: HomeRegion
    type: String
    value: eu-central-1              # Plan Decision 2
  - key: BudgetsEmail
    type: String
    value: aws-managers+budgets@<domain>
  - key: SecurityHighEmail
    type: String
    value: aws-managers+sec-high@<domain>
  - key: SecurityMediumEmail
    type: String
    value: aws-managers+sec-med@<domain>
  - key: SecurityLowEmail
    type: String
    value: aws-managers+sec-low@<domain>
  - key: TgwAsn
    type: String
    value: "64512"                   # private ASN range 64512–65534
```

**Pitfalls:**
- ⚠️ **`AcceleratorPrefix` controls the NAME of every LZA-managed resource.** Changing it after the first deploy is a cascading rename of every SCP, role, KMS key, bucket — effectively a teardown (Plan Decision 1). Set once, never touch.
- **`HomeRegion` + `EnabledRegions`** — single-region is simplest; every extra region multiplies cost and the number of stacks. Match the plan exactly.
- 🚫 **Anti-pattern:** don't define CIDR variables here if you're going **IPAM-less** (the current default). Put explicit CIDRs in `network-config.yaml` instead — scattering CIDRs across replacements makes the network plan unreadable.

---

## 2 — `accounts-config.yaml`

**What it does:** declares every account LZA creates or invites, and its OU.

> **Auto-generated.** Running the intake planner ([`intake/`](../intake/README.md)) emits a ready-to-commit `accounts-config.yaml` from the workbook's account list (type `Mandatory` → `mandatoryAccounts`, else `workloadAccounts`). Use it as-is; the notes below are for review/edits.

```yaml
mandatoryAccounts:
  - name: Management
    description: Org management
    email: aws-managers+management@<domain>
    organizationalUnit: Root
  - name: LogArchive
    description: Central logging
    email: aws-managers+log@<domain>
    organizationalUnit: Security
  - name: Audit
    description: Security tooling delegated admin
    email: aws-managers+audit@<domain>
    organizationalUnit: Security
workloadAccounts:
  - name: Network
    email: aws-managers+network@<domain>
    organizationalUnit: Infrastructure
  - name: <customer>-prd
    email: aws-managers+prd@<domain>
    organizationalUnit: Workloads/Prod
```

**Pitfalls:**
- ❌ **Don't rename the mandatory accounts** (`Management`, `LogArchive`, `Audit`) — LZA and CT key off these exact names.
- ❌ **Every email must be globally unique across all of AWS** and a real inbox. Reusing a closed account's email is impossible (Plan Decision 4).
- **OU paths are relative to org root**, slash-delimited (`Workloads/Prod`), and the OU must already exist in `organization-config.yaml`.
- ⏳ **~10 accounts/hour** creation limit (Organizations). 15+ at launch → two-pass deploy (flagged in the plan).
- Existing accounts to bring in → they're **invited**, not created; ensure the email matches the real account's root email.

---

## 3 — `organization-config.yaml`

**What it does:** the OU tree plus all org-level policies (SCPs, RCPs, tag policies, backup policies) and their attachment points.

> **OU tree auto-generated.** The intake planner ([`intake/`](../intake/README.md)) emits `organization-config.yaml` with the `organizationalUnits` block already built from the workbook (Root implicit, slash-paths, `ignore: true` on parked OUs). You then add the policy blocks (SCPs/tag/backup) below into that file.

```yaml
enable: true
organizationalUnits:
  - name: Security
  - name: Infrastructure
  - name: Workloads
  - name: Workloads/Dev
  - name: Workloads/Test
  - name: Workloads/Prod
  - name: Workloads/Sandbox
  - name: Suspended
    ignore: true                     # parked accounts, baseline not applied
quarantineNewAccounts:
  enable: true
  scpPolicyName: Quarantine
serviceControlPolicies:
  - name: Core-Guardrails-1
    description: Region + root + critical-service guardrails
    policy: service-control-policies/core-guardrails-1.json
    type: customerManaged
    deploymentTargets:
      organizationalUnits: [Security, Infrastructure, Workloads]
  - name: Quarantine
    policy: service-control-policies/quarantine.json
    type: customerManaged
    deploymentTargets: { organizationalUnits: [] }   # attached dynamically
```

**Pitfalls — read this section twice, it's where deploys die:**
- **`quarantineNewAccounts`**: LZA attaches a deny-all `Quarantine` SCP to every new account at the start of the Accounts stage, then releases it at Finalize. **The Quarantine SCP (and every guardrail SCP) MUST exempt the `stacksets-exec-*` principal** — otherwise CloudFormation StackSets (which CT uses to baseline the account) gets an explicit deny and the whole pipeline fails. See `/lza-troubleshoot` → "stacksets-exec" symptom and the `patch_scps.py` script. This is the single most common LZA failure.
- **SCP attachment quota**: max 5 SCPs per target (OU/account), including AWS-managed. Design `Core-Guardrails-1`/`-2` to fit under the cap; that's *why* there are numbered guardrail files — to pack policy statements into fewer attachments.
- **SCPs that block CT itself**: any SCP denying `cloudformation:*`, `iam:*`, or specific regions can lock out CT's own automation. Always allow the CT execution roles.
- **Tag policies** (`org` tag, `s3` tag, `nsf` tag): start **declarative** (report-only). Promoting to **`enforced_for`** blocks non-compliant tag operations on existing resources — premature enforcement breaks running workloads (Plan Decision 8).
- **Backup policies + AWS Backup Vault Lock**: Vault Lock in *compliance mode* is **irreversible** — you cannot shorten retention or delete recovery points until the lock expires. Use *governance mode* until retention is final.

---

## 4 — `global-config.yaml`

**What it does:** Control Tower binding, org-wide logging, the global tag block, SNS subscribers, budgets.

```yaml
homeRegion: '{{ HomeRegion }}'
enabledRegions: ['{{ HomeRegion }}']
controlTower:
  enable: true                       # CT owns OU/account lifecycle
managementAccountAccessRole: AWSControlTowerExecution
cloudwatchLogRetentionInDays: 731    # applies to ALL org log groups
logging:
  account: LogArchive
  cloudtrail: { enable: true, organizationTrail: true }
  sessionManager: { sendToS3: true, sendToCloudWatchLogs: true }
tags:
  - key: Accelerator
    value: '{{ AcceleratorPrefix }}'
  - key: nsf:managed-by
    value: lza
  - key: nsf:client
    value: <customer>
snsTopics:
  topics:
    - name: SecurityHigh
      emailAddresses: ['{{ SecurityHighEmail }}']
budgets:
  - name: monthly-overall
    amount: 5000
    unit: USD
    subscribers: [{ address: '{{ BudgetsEmail }}', type: EMAIL }]
```

**Pitfalls:**
- **`controlTower.enable: true`** makes CT the owner of OUs/accounts. Must match the Step 7 decision in `/lza-bootstrap`. Flipping it later is a rebuild.
- **`cloudwatchLogRetentionInDays`** applies org-wide — pick once; lowering it later deletes log history.
- **Global tag block** drives cost allocation — these tags must be **activated in Billing → Cost allocation tags** to actually show up in Cost Explorer (a manual console step LZA can't do for you).
- **SNS email subscribers** require **manual confirmation** of the subscription email — until confirmed, no alerts flow.

---

## 5 — `security-config.yaml`

**What it does:** delegated-admin security services, IAM Identity Center (if LZA-managed), Security Hub standards + findings suppression, password policy, central KMS.

```yaml
centralSecurityServices:
  delegatedAdminAccount: Audit
  guardduty: { enable: true }
  securityHub:
    enable: true
    standards:
      - { name: 'AWS Foundational Security Best Practices v1.0.0', enable: true }
      - { name: 'CIS AWS Foundations Benchmark v1.4.0', enable: true }
  macie: { enable: true }
accessAnalyzer: { enable: true }
iamPasswordPolicy: { minimumPasswordLength: 14, maxPasswordAge: 90 }
```

**Pitfalls:**
- **Delegated admin = Audit account** for all security services — never the management account (AWS best practice; CT expects Audit).
- **Security Hub findings suppression**: the noisy S3 controls commonly suppressed for LZA-managed buckets are **S3.1, S3.6, S3.7, S3.9, S3.11, S3.15, S3.17, S3.20**. Suppress with documented rationale, don't disable the whole standard.
- **IAM Identity Center**: configure here **only if LZA manages IDC**. If CT created/owns IDC, defining permission sets here can conflict — confirm against `/lza-bootstrap` Step 8.
- **Central KMS key**: the key LZA uses for log/bucket encryption — its policy must allow the log-delivery and CT service principals or logging stacks fail.

---

## 6 — `network-config.yaml`

**What it does:** the entire network — Transit Gateway, VPCs, subnets, Network Firewall, endpoints, flow logs. **The largest, most error-prone file.** Use the CIDR plan (`network-cidr-plan.md`) from Plan Decision 5 as the source of truth.

> **Don't hand-write the `vpcs[].subnets[]` blocks.** They come from the intake planner ([`intake/`](../intake/README.md)): fill subnet tiers + IP counts + on-prem CIDRs in `requirements.<customer>.yaml`, run `plan_subnets.py`, and paste the generated **`network-config.snippet.yaml`** here. CIDRs are already overlap-checked against on-prem and sized per requested IP count — re-run the planner (don't hand-edit) if requirements change, so the overlap guard stays honest.

**Core pattern — Transit Gateway with route tables:**
```yaml
transitGateways:
  - name: Main-TGW
    account: Network
    region: '{{ HomeRegion }}'
    asn: 64512
    routeTables:
      - name: rt-spoke         # workload VPCs attach here
      - name: rt-firewall      # inspection VPC, forces east-west through NFW
    shareTargets:
      organizationalUnits: [Infrastructure, Workloads]   # see pitfall
```

**The core 3-VPC pattern (Infrastructure):**
- **Ingress/Egress** (Perimeter account) — public ALBs, 3× NAT GW for egress
- **Inspection** (Network account) — AWS Network Firewall endpoints, one per AZ
- **SharedServices** (SharedServices account) — central endpoints, AD, monitoring

**Explicit VPC entry (post-IPAM — IPAM removed, use explicit CIDRs):**
```yaml
vpcs:
  - name: <customer>-prd
    account: <customer>-prd
    region: '{{ HomeRegion }}'
    cidrs: ['10.1.0.0/16']
    subnets:
      - { name: private-a, availabilityZone: a, ipv4CidrBlock: '10.1.32.0/19' }
      # ... loadbalancer/private/database/firewall/endpoints/tgw tiers × 3 AZs
    transitGatewayAttachments:
      - { name: prd-attach, transitGateway: { name: Main-TGW, account: Network },
          routeTableAssociations: [rt-spoke], routeTablePropagations: [rt-spoke] }
```

**Pitfalls:**
- 🚫 **`vpcTemplates` vs explicit `vpcs`**: IPAM was removed → **use explicit `vpcs` entries with hard CIDRs**. `vpcTemplates` (which relied on IPAM auto-allocation) will not allocate as expected.
- **CIDR overlaps** are the deploy-killer: every VPC CIDR must be unique across the whole TGW domain *and* not overlap on-prem/peer ranges (Plan Decision 5). Cross-check against `network-cidr-plan.md` before deploying.
- **Central endpoints VPC vs per-VPC interface endpoints**: central is cheaper at scale but adds a TGW hop + Route 53 resolver complexity; per-VPC is simpler but costs ~$7/endpoint/AZ/mo each. Decide per the plan; don't mix accidentally.
- **Network Firewall `rules.txt`** uses **Suricata** syntax. A single malformed rule fails the whole NFW deploy. Keep an allow-most baseline + explicit denies; test rule syntax before pushing.
- **3-AZ subnet layout**: stick to the per-workload pattern from the plan (loadbalancer /22, private /19, database /22, firewall /28, endpoints /26, tgw /28 per AZ). Off-pattern subnets break the reusable templates.
- **VPC Flow Logs**: set the format/destination to the central log bucket; mismatched log-group names break dynamic partitioning (see security-config + `lza-validate`).

---

## 7 — `iam-config.yaml`

**What it does:** SAML federation providers, identity sources, group/role mappings.

```yaml
providers:
  - name: ExternalIdP
    metadataDocument: iam-config/metadata/idp-metadata.xml
roleSets:
  - deploymentTargets: { organizationalUnits: [Workloads] }
    roles:
      - name: WorkloadAdmin
        assumedBy: [{ type: principalArn, principal: '<sso-or-saml-arn>' }]
        policies: { awsManaged: [AdministratorAccess] }
```

**Pitfalls:**
- SAML metadata XML must be current — expired IdP metadata silently breaks federation.
- Role `assumedBy` ARNs must match the actual IDC/SAML principal exactly.
- Keep this minimal if IDC permission sets already cover human access — duplicate paths cause confusion.

---

## 8 — `customizations-config.yaml`

**What it does:** deploys custom CloudFormation (stacks or StackSets) through the LZA pipeline. **Only fill this if the customer needs resources LZA doesn't natively manage.**

```yaml
customizations:
  cloudFormationStacks:
    - name: CustomBaseline
      template: customizations/custom-baseline.yaml
      runOrder: 1
      deploymentTargets: { organizationalUnits: [Workloads] }
```

**Pitfalls:**
- **StackSets vs stack instances**: StackSets fan out across many accounts/regions (use for org-wide baselines); single stacks target specific accounts. Picking wrong causes either missing coverage or per-account drift.
- A failing custom template fails the **Deploy** stage — test custom CFN independently first.

---

## Common pitfalls index (quick reference)

| Pitfall | Consequence | Where |
|---|---|---|
| `AcceleratorPrefix` change after first deploy | Catastrophic full rename / teardown | replacements |
| SCP without `stacksets-exec-*` exemption | Pipeline fails every run | organization → see `/lza-troubleshoot` |
| CIDR overlap when adding VPCs | Deploy stage fails / no routing | network |
| Tag policy `enforced_for` turned on early | Breaks existing non-compliant resources | organization |
| KMS keys-per-region quota hit | Logging/security stacks fail | global/security → check quota in `/lza-bootstrap` |
| `vpcTemplates` used without IPAM | VPCs don't allocate | network |
| Backup Vault Lock in compliance mode | Irreversible retention | organization |

---

## When to re-invoke this skill

- New config file changes for a feature → edit the specific file, re-read its pitfall list.
- Adding accounts/VPCs day-2 → use `/lza-add-account` (it scopes the edits for you).
- New compliance standard → revisit security-config + organization-config.

## Related skills

- Before: `/lza-bootstrap` — must be complete; provides the config repo + installed pipeline
- After: `/lza-deploy` — push these files and run the pipeline
- Day-2 edits: `/lza-add-account`
- When a config change breaks the pipeline: `/lza-troubleshoot`
