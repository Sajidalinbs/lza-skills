---
name: lza-plan
description: Use at the start of a new AWS Landing Zone Accelerator engagement for a customer. Captures the questions you must answer BEFORE writing any LZA YAML — organizational structure, accounts, prefix, regions, CIDR plan, SSO strategy, compliance scope. Produces a planning artifact that drives every downstream skill (lza-bootstrap, lza-configure, lza-deploy). Invoke once per new customer.
---

# `/lza-plan` — Pre-deployment planning for a new LZA engagement

> **Validated against LZA version:** 1.15.0
> **Predecessor skill:** none — this is where you start
> **Successor skill:** `/lza-bootstrap`

## Purpose

Most LZA pain comes from decisions that look small at the start and become irreversible by Day 30. This skill makes you stop and answer them deliberately before they harden in concrete:

- Which prefix?
- How many regions?
- What OU structure?
- How many accounts, in which OUs, with what emails?
- What CIDR ranges, and how are they split?
- IAM Identity Center already in use?
- Compliance regime?

The output of this skill is a **planning document** (`<customer>-lza-plan.md` — template included below) that is the single source of truth for every subsequent config decision.

---

## How to use this skill

This skill operates in one of **two modes**. Pick based on whether a filled intake document already exists — **Mode A is the real-world default.**

### Mode A — Intake-document-first (the normal flow) ⭐

You usually **cannot** run an 8-question interview live in front of the customer: they won't have root emails, CIDR ranges, IdP details, or compliance scope at their fingertips, and these are exactly the irreversible decisions you must not guess. So the normal engagement flow is **share a form first, ingest it later**:

1. **Before the session,** send the customer the **intake & requirements document** to complete at their own pace. It ships with these skills at [`intake/lza-intake-form.md`](../intake/lza-intake-form.md) — 16 sections covering contacts + break-glass, **email distribution** (management root email, alias base + plus-addressing test, per-account root emails, security/billing/ops notification lists and who confirms the SNS subscriptions), current AWS state, regions, prefix, OU tree, account inventory, **on-prem/VPN/DX CIDR confirmation** (complete-list table + a signed confirmation + approval of the proposed supernet), DNS/egress/ingress, SSO/IdP, config repo + connection, compliance, tagging/cost, logging/encryption/backup, timeline, and sign-off. Render it as Word for the customer:

   ```bash
   python3 intake/make_docx.py intake/lza-intake-form.md --customer "<Customer>"
   # → <Customer>_AWS_LZA_Intake.docx   (stdlib only — no python-docx/pandoc needed)
   ```

   In parallel, pre-fill the **account + network/IP design** (OU tree, account list, VPC/subnet/CIDR layout) using Decision 5's tooling and ship it alongside as a design spreadsheet for the customer to approve. The form is the customer's homework; the spreadsheet is our proposed design.
2. **When the customer returns the filled documents,** invoke `/lza-plan` pointed at them. The skill's job is now to **ingest and reconcile**, not to interview:
   - **Parse every provided artifact.** `.docx` → unzip and read `word/document.xml`, replace `</w:p>`/`</w:tc>` with newlines/separators, strip tags, unescape entities. `.xlsx` → `openpyxl` (`data_only=True`), iterate rows per sheet. Do **not** ask for any value the documents already contain.
   - **Reconcile sources against each other.** When two documents disagree on an **irreversible** field (HomeRegion, AcceleratorPrefix, CIDR base, account root emails), **STOP and surface the conflict — never silently pick one.** Ask the customer/engineer which is authoritative, then record the resolution in an **Open items & discrepancies** table in the plan. *(Field-tested example: an intake form gave HomeRegion `us-east-2` while the design spreadsheet was built entirely in `eu-central-1` — a full-rebuild-if-wrong conflict only a human can resolve. CIDRs are region-agnostic, so the IP design survived once the region was confirmed and the spreadsheet's region label was corrected.)*
   - **Validate the handed-over network design.** Confirm every subnet sits inside its VPC CIDR, and that there are no VPC-vs-VPC or subnet-vs-subnet overlaps (a quick `ipaddress` pass over the spreadsheet). Cross-check against the customer's on-prem CIDR list. Treat any blank-but-critical field (e.g. on-prem CIDRs left empty) as an **Open item**, not as "none."
   - Map the ingested answers onto the 8 decisions below, then write the plan.
3. Ask the customer **only** the questions still genuinely open after ingestion + reconciliation — typically the FOLLOW-UP items they left blank.

> **Keep the intake form and this skill in sync.** [`intake/lza-intake-form.md`](../intake/lza-intake-form.md) and the 8 decisions here are two views of the same questionnaire — when you add or change a decision, update the form too, and vice-versa. (Its §16 mapping table shows which form section feeds which decision.) A question that lives only in the skill (asked live) but not in the form will routinely arrive at the session unanswered.

### Mode B — Live walk-through (fallback / greenfield scoping)

When no intake document exists yet (an early scoping call, an internal demo), walk the customer through the 8 decisions below **in order**. For each one:

1. State the decision being made.
2. Explain what it controls and what's reversible vs irreversible.
3. **Lead with a concrete, opinionated default** — propose the actual values (prefix, OU tree, account list, VPCs + subnets + CIDRs), not a blank page.
4. Ask only the questions needed to *confirm or correct* that default.
5. Record the answer in the planning document.

Don't move to the next decision until the current one is answered and recorded.

> **Be opinionated — make it easy to say yes.** The customer should mostly be *approving* a recommended design, not architecting from scratch. For each decision, present the default as "here's what we recommend — anything you need different?" Only open up the full design space when the customer has a real constraint (on-prem CIDR overlap, compliance scope, branding). This is fastest for the customer and produces the cleanest, most supportable landing zone. The network decision (Decision 5) is the clearest example: propose a full VPC/subnet/CIDR layout and let the customer approve it after a single on-prem overlap check.

**Both modes** end the same way: when all 8 decisions are recorded, write the planning document to `<customer>-lza-plan.md` in the customer's repo root — including the **Open items & discrepancies** table from any reconciliation.

### Setup — auto-provision the intake tooling (run this FIRST, automatically)

Decision 5 (network) runs the Python tooling that ships with these skills in the **`intake/`** folder. When you work in a **separate customer/demo folder** it isn't there. **As your very first action when this skill is invoked, run the snippet below** to copy it in automatically — it's idempotent (does nothing if `intake/` already exists) and self-resolves the source from the installed skill's location:

```bash
if [ ! -d ./intake ]; then
  src="$(dirname "$(readlink ~/.claude/skills/lza-plan 2>/dev/null || echo ~/.claude/skills/lza-plan)")/intake"
  if [ -d "$src" ]; then
    cp -R "$src" ./intake && echo "✓ provisioned intake/ from $src"
  else
    echo "⚠ intake/ not found near the skill — ask the user for the lza-skills repo path, then: cp -R <repo>/intake ./intake"
  fi
fi
```

This makes the engagement self-contained (plan + the tooling that generated it travel together). The planner then runs as `python3 intake/plan_subnets.py requirements.<customer>.yaml`. Prereqs: `python3`, `openpyxl`, `pyyaml`. If the snippet can't locate the source (skill installed by copy, not symlink), ask the user for the lza-skills repo path and copy from there before reaching Decision 5.

---

## Decision 1 — `AcceleratorPrefix`

**What it controls:** the name prefix of every LZA-managed AWS resource (SCPs, IAM roles, KMS keys, S3 buckets, SNS topics, CloudFormation stacks, Lambda functions). Every resource will be named `<prefix>-<rest-of-name>`.

**Reversibility:** ❌ **Effectively irreversible after the first pipeline run.** Changing the prefix forces LZA to delete and recreate every resource, breaks IAM trust policies, breaks CloudTrail bucket names, etc. AWS provides no migration path.

**Default:** `AWSAccelerator` (LZA's stock default).

**Customer-specific alternative:** lowercase customer name (e.g. `acme`, `contoso`). Shorter resource names, easier to grep in CloudTrail. We've tested this with multiple customers — it works, **but only if set before the first deploy**.

**Questions to ask:**
- Does the customer have a branding requirement that surfaces in AWS resource names?
- Are there existing resources in the management account using `AWSAccelerator-*` that we'd conflict with?
- Will any third-party tools depend on a specific naming convention?

**Record:**
```
AcceleratorPrefix: <value>
Rationale: <one-line why>
```

---

## Decision 2 — Region strategy

**What it controls:** `HomeRegion` (the LZA management plane region — where CodePipeline, CodeBuild, the management S3 bucket live) and `EnabledRegions` (the list of regions where workload resources are deployed and Control Tower governs).

**Reversibility:**
- Adding regions later: ✅ supported
- Removing regions later: ⚠️ painful — requires manual cleanup
- Changing HomeRegion: ❌ requires full LZA redeployment

**Default:** single region in the customer's primary geo.

**Questions to ask:**
- Where are the customer's users and data sovereignty requirements?
- Is there a DR region requirement? (LZA can govern multiple regions but each adds cost and complexity)
- Is the customer in an opt-in region (e.g. Cape Town, Bahrain, Jakarta, Hyderabad, Zurich, Hong Kong, UAE)? If yes, `enableOptInRegions: true` in global-config and CT must explicitly include the region.

**Record:**
```
HomeRegion: <region>
EnabledRegions: [<region>, ...]
OptIn regions used: yes/no
```

**Cost note:** every governed region runs CT, Config recorders, GuardDuty, Security Hub — non-trivial fixed cost per region (~$100-300/mo/region just for the baseline before any workload).

---

## Decision 3 — OU structure

**What it controls:** the AWS Organizations OU tree. Every account lives in an OU, and SCPs / RCPs / tag policies / backup policies are attached at the OU level (with inheritance to child OUs and accounts).

**Reversibility:**
- Adding new OUs: ✅ trivial
- Moving an account between OUs: ⚠️ possible but causes baseline drift
- Renaming/deleting an OU with accounts in it: ❌ requires moving accounts first, then deleting
- **Renaming an OU after CT controls are attached: ❌ effectively impossible.** LZA's CDK derives CFN logical IDs from OU names. Renaming produces new logical IDs that try to claim physical resources still owned by the old ones in the same stack — CloudFormation refuses (`already exists in stack`). There is no graceful forward fix; the only safe path is to revert the rename. **Treat OU names as immutable once `/lza-deploy` has run.** Spend the time at this step getting them right. See the `/lza-troubleshoot` "OU rename trap" runbook for the full failure mode.
- **Deleting an OU that exists in AWS: ⚠️ manual cleanup required.** LZA never auto-deletes OUs. Removing one from `organization-config.yaml` triggers a `ValidateEnvironmentConfig` failure in the Prepare stack *before* CT controls/baselines can be torn down. Sequence as a two-phase change: (1) Pipeline moves accounts out of the doomed OU; (2) Operator manually disables CT controls + the baseline on the empty OU, deletes the OU via Organizations API, then removes it from config and re-runs. The CT baseline-disable API serializes org-wide — clean OUs sequentially through that step. See the `/lza-troubleshoot` "OU delete trap" runbook and `scripts/cleanup_empty_ous.py`.

**Default (the LZA reference structure):**
```
Root
├── Security                 ← LogArchive, Audit (mandatory)
├── Infrastructure           ← Network, SharedServices, Perimeter
├── Workloads                ← parent OU for application workloads
│   ├── Dev
│   ├── Test
│   ├── Prod
│   └── Sandbox
└── Suspended (ignore: true) ← parking for decommissioned accounts
```

**Variations to consider:**
- **By environment** (default above) — clean separation, common pattern
- **By business unit** (e.g. `Workloads/TeamA/Prod`, `Workloads/TeamB/Prod`) — useful for chargeback or strict isolation
- **By compliance scope** (e.g. separate OUs for PCI / HIPAA-scoped accounts) — required if compliance regimes differ across workloads

**Questions to ask:**
- How does the customer team think about environments? (env-first, BU-first, compliance-first)
- Will any workload accounts need fundamentally different guardrails? (e.g. PCI requires extra SCPs)
- Is there a parked / suspended account convention they already use?

**Record:**
```
OU tree:
  Root
    Security
    Infrastructure
    Workloads
      <list each leaf OU>
    Suspended (ignore: true)
```

---

## Decision 4 — Account inventory

**What it controls:** the AWS accounts LZA will create (or invite, for existing ones) and where they live in the OU tree.

**Reversibility:**
- Adding accounts later: ✅ trivial (`/lza-add-account`)
- Closing accounts: ⚠️ AWS-side closure is permanent and there's a 90-day cooldown
- Moving accounts: ⚠️ causes drift, requires baseline reset
- Email aliases: ❌ each account email must be **globally unique within AWS** — once used, never reusable

**Mandatory accounts (always created):**
| Name | OU | Purpose |
|---|---|---|
| Management | Root | Org owner, holds CT, LZA pipeline, IAM IDC |
| LogArchive | Security | Central log archive |
| Audit | Security | Delegated admin for security services |

**Standard workload accounts:**
| Name | OU | Purpose |
|---|---|---|
| Network | Infrastructure | TGW, NFW, central DNS, inspection VPC |
| SharedServices | Infrastructure | AD, jump hosts, monitoring, central VPC endpoints |
| Perimeter | Infrastructure | Ingress/egress VPCs, NAT GWs, public ALBs |

**Customer workload accounts:**
- one per environment per app team, or one per BU per environment, depending on OU structure

### Emails — ASK, don't assume ⚠️

Account emails are irreversible (globally unique, never reusable), so collect them deliberately:

1. **Management account email — ASK FOR IT EXPLICITLY.** The management account almost always **already exists** (it's the account you run LZA from), so it has a **specific, pre-existing root email that you cannot guess**. Never assume `aws-managers+management@<domain>` for it. Ask the customer: *"What is the existing root email of your AWS management account?"* and record exactly what they give you.
2. **Alias base for the other (to-be-created) accounts — confirm the pattern, then derive.** LogArchive, Audit, Network, SharedServices, Perimeter, and the workload accounts are created fresh, so they use the plus-alias convention. Ask: *"For the new accounts, can we use `aws-managers+<account>@<domain>` (e.g. `aws-managers+log@<domain>`)? Confirm this base inbox exists and accepts plus-addressed mail."* Then derive each as `aws-managers+<account>@<domain>`.
3. **Confirm plus-addressing works** — some corporate mail systems silently drop `+` tags. If so, the customer must supply a distinct real inbox per account instead.

So: **one explicit answer for Management**, **one confirmed base+pattern for everything else**. Do not fill the Management email from the pattern.

**Questions to ask:**
- **What is the existing management account root email?** (explicit — do not assume)
- Alias base + does plus-addressing work? (`aws-managers+<account>@<domain>`)
- How many workload accounts at launch? Names? OUs?
- Does the customer have existing AWS accounts to bring into the org? (use `invite-account-to-organization`, not `create-account`)
- Is there an emergency / break-glass account requirement? (SEC03-BP03 recommends one)

**Account creation rate limit:** AWS Organizations limits account creation to ~10/hour. If creating 15+ accounts at first deploy, the pipeline may stall — plan a two-pass deployment if needed.

**Record:**
```
Accounts:
  - Management   | Root            | <EXISTING root email — ASK; do NOT derive from pattern>
  - LogArchive   | Security        | aws-managers+log@<domain>
  - Audit        | Security        | aws-managers+audit@<domain>
  - Network      | Infrastructure  | aws-managers+network@<domain>
  - SharedServices | Infrastructure | aws-managers+shared-services@<domain>
  - Perimeter    | Infrastructure  | aws-managers+perimeter@<domain>
  - <customer>-prd | Workloads/Prod | aws-managers+prd@<domain>
  - <customer>-dev | Workloads/Dev  | aws-managers+dev@<domain>
  - ...
Alias base: aws-managers+<account>@<domain>   (for CREATED accounts only)
Plus-addressing confirmed working: yes/no
```

---

## Decision 5 — CIDR / network plan

**What it controls:** the IP address space LZA will use for every VPC and subnet. Mistakes here are extremely painful to correct after deployment — every VPC keeps its CIDR for its entire lifetime.

**Reversibility:** ⚠️ Adding a *secondary* CIDR to a VPC is supported; changing the primary is not. CIDR overlaps with peer networks (on-prem, partner clouds) require renumbering one side — assume the customer's existing networks are immovable.

### Be opinionated: PROPOSE this default network, then check overlap

Don't ask the customer to design a network. **Present this concrete default layout** (names + CIDRs), then run the **one** gating check — on-prem overlap. If it's clean, the customer approves and you proceed. Only customize if there's an overlap or a special requirement.

> Design constraints baked into this default: **explicit CIDRs (no IPAM)**, and **no DNS hub VPC and no central interface-endpoints VPC** — each spoke gets its own small `endpoints` tier instead.

> **Why base `10.240.0.0/13` (10.240–10.247)?** Most customer on-prem lives in the low `10.0–10.x` ranges, so defaulting LZA to a *high* 10-block dramatically cuts the chance of an overlap you'd have to redesign around. This is the opinionated, expert default — same reasoning behind proven field deployments.

**Proposed default — hub VPCs (Network + Perimeter accounts), supernet `10.240.0.0/13`:**

| VPC | Account | CIDR | Purpose |
|---|---|---|---|
| Ingress | Perimeter | `10.240.0.0/22` | public ALB/WAF |
| Egress | Perimeter | `10.240.4.0/24` | 3× NAT GW |
| Inspection | Network | `10.240.5.0/24` | Network Firewall endpoints |
| SharedServices | SharedServices | `10.240.7.0/24` | shared tooling |

**Proposed default — workload spokes (one `/16` each):**

| Spoke | Account | CIDR |
|---|---|---|
| Prod | `<customer>-prd` | `10.242.0.0/16` |
| Dev | `<customer>-dev` | `10.243.0.0/16` |
| Test | `<customer>-tst` | `10.244.0.0/16` |
| (future) | — | `10.245.0.0/16+` reserved |

**Proposed default — per-spoke subnet tiers (3 AZs each → 15 subnets/spoke), `X` = 242/243/244:**

| Tier (name) | Per-AZ CIDR (a / b / c) | Size | Purpose |
|---|---|---|---|
| `loadbalancer` | `10.X.0.0/22` · `10.X.4.0/22` · `10.X.8.0/22` | /22 (~1019) | ALB/NLB ENIs |
| `private` | `10.X.32.0/19` · `10.X.64.0/19` · `10.X.96.0/19` | /19 (~8187) | app/compute |
| `database` | `10.X.128.0/22` · `10.X.132.0/22` · `10.X.136.0/22` | /22 | Aurora/RDS |
| `endpoints` | `10.X.140.64/26` · `10.X.140.128/26` · `10.X.140.192/26` | /26 | per-VPC interface endpoints |
| `tgw` | `10.X.141.0/28` · `10.X.141.16/28` · `10.X.141.32/28` | /28 | TGW attachment ENIs |

> The per-AZ CIDRs above are **illustrative**. The planner assigns the exact non-overlapping addresses (largest tier first) and the generated review Excel (`<customer>-network-plan.xlsx`) is the **source of truth**; the sizes shown are the minimum that fit each tier's default IP count.

**Present it like this:** *"Here's the proposed network — hub VPCs plus Prod/Dev/Test spokes, all under 10.240–10.244. Does any of this overlap your on-prem, VPN, or Direct Connect ranges?"*

### The single gate — on-prem overlap

This is the only thing that can force a change. Ask for the customer's reachable ranges, then validate:
- Get **every** on-prem / VPN / Direct Connect / cloud-peer CIDR.
- Run the proposed plan through the intake planner (below) — it **refuses** any overlap.
- **If clean → customer approves → proceed.**
- **If `10.x` is reserved on-prem** → don't redesign tier-by-tier; just **shift the whole plan**: substitute the `10.` base with `172.16.` or a high block like `10.240.` and re-run. Same structure, new base.

**Questions to ask (only these):**
- Any on-prem / VPN / Direct Connect / cloud-peer CIDRs we must avoid? (Get the full list.)
- Is `10.0.0.0/16–10.3.0.0/16` free, or is `10.x` reserved on-prem (→ shift the base)?
- More than 3 workload spokes at year 3? (Reserve more `/16`s now.)

**Record:**
- Produce the CIDR plan as a **review Excel** (`<customer>-network-plan.xlsx`) — see tooling below — and note the approved base + any shift in `network-cidr-plan.md`.

**Tooling — the planner generates and overlap-checks the proposal for you.** A **pre-generated view of this exact default** ships at [`intake/default-network-plan.xlsx`](../intake/default-network-plan.xlsx) (and `.csv`) — open it to show the customer every baseline VPC/subnet/CIDR instantly, before editing anything. To produce the customer's own plan, use the intake planner in [`intake/`](../intake/README.md): start from the ready-made opinionated default [`intake/requirements.default.yaml`](../intake/requirements.default.yaml) (the exact layout above) — the engineer only edits the **emails** and the **on-prem CIDR list**. Then `plan_subnets.py` sizes each subnet, carves non-overlapping CIDRs, **refuses any layout that overlaps on-prem**, and emits the **review Excel** for customer sign-off plus `accounts-config.yaml`, `organization-config.yaml`, and `network-config.snippet.yaml` for `/lza-configure`. For a custom layout (e.g. "App A = 10 subnets, App B = 12"), copy it to `requirements.<customer>.yaml` and adjust the `tiers`.

---

## Decision 6 — IAM Identity Center (SSO) strategy

**What it controls:** how humans and federated identities access the AWS accounts.

**Reversibility:**
- Disabling org-level IDC: ⚠️ requires CT to be torn down and rebuilt (we've hit this in the field — painful)
- Migrating IDC instance between regions: ❌ rebuild required
- Changing identity source (built-in → external IdP): ✅ supported

**Three common starting states:**

| State | Recommended approach |
|---|---|
| **No SSO yet** | Let CT create IAM Identity Center fresh as part of landing zone setup (`enableIdentityCenterAccess: true`). Easy path. |
| **SSO already configured in management account, but no other LZA features deployed** | Either accept CT's "take over existing IDC" path (works in console-setup), OR disable SSO trusted access first and let CT rebuild (see `/lza-troubleshoot` for the trusted-services trap). |
| **SSO with active users in non-CT regions or with custom permission sets** | Inventory permission sets and account assignments FIRST. After CT setup, you may need to recreate them. |

**Identity source decision:**
- Built-in IDC directory (start here unless you have an existing IdP)
- External SAML 2.0 IdP (Azure AD / Entra, Okta, Google Workspace, Ping)
- Active Directory (via AD Connector)

**Questions to ask:**
- Is IAM Identity Center already in use? If yes, in which region? How many users?
- What's the customer's primary identity provider? (often the answer: "we use Microsoft 365" → use Entra ID)
- Permission sets needed (Admin, ReadOnly, Developer, Auditor, etc.)?
- Who's the break-glass user? (Root + an IAM user separate from SSO)

**Record:**
```
IAM Identity Center:
  Region: <home region>
  Identity source: <built-in / Entra ID / Okta / etc.>
  Existing instance: yes / no
  Migration path required: yes / no  (if yes, schedule downtime window)
  Permission sets:
    - <name>: <managed policies + customer managed policies>
    - ...
```

---

## Decision 7 — Compliance / regulatory scope

**What it controls:** which AWS Security Hub standards to enable, which compliance frameworks to baseline against, which controls map to which OUs.

**Reversibility:** ✅ Mostly reversible — enabling/disabling standards is straightforward.

**Common standards in LZA:**
- AWS Foundational Security Best Practices (FSBP) — almost always on
- CIS AWS Foundations Benchmark v1.4 / v3.0 — usually on
- PCI DSS — only if scope requires
- NIST 800-53 — for regulated industries
- NIST CSF v2.0 — newer, growing
- AWS Resource Tagging — optional, complements tag policies

**Compliance regimes that change LZA decisions:**
- **PCI DSS scope:** dedicated OU + dedicated SCPs + more restrictive networking, separate KMS keys
- **HIPAA:** BAA with AWS required, eligible-services-only constraints, encryption mandates
- **FedRAMP:** GovCloud region (not commercial AWS — different LZA path entirely)
- **SOC 2:** affects logging retention and access control
- **GDPR / data residency:** affects HomeRegion / EnabledRegions choice and S3 bucket regions

**Questions to ask:**
- What compliance frameworks must the customer meet?
- Are there in-scope vs out-of-scope workloads?
- Customer's preferred CIS version?
- Data residency requirements? (drives region choice — already decided in Decision 2 but flag if compliance forces it)

**Record:**
```
Compliance:
  Standards: <list>
  Frameworks: <list>
  Data residency: <region constraint>
  Scope notes: <which OUs/accounts are in-scope>
```

---

## Decision 8 — Tagging strategy

**What it controls:** the org-wide tag taxonomy. Used for cost allocation, automation, compliance, and the AWS Backup tag-based plan selection.

**Reversibility:** ✅ Adding tags is easy. Renaming or removing tag KEYS after they're widely applied is painful — every resource has to be re-tagged.

**Recommended minimum tag taxonomy:**
| Tag key | Allowed values | Purpose |
|---|---|---|
| `<org>:client` | the customer name | Identifies the customer (useful for MSPs serving multiple customers) |
| `<org>:env` | mgmt, audit, log-archive, network, shared, prod, staging, test, dev, sandbox, perimeter | Environment classification |
| `<org>:managed-by` | lza, terraform, manual, cloudformation | What owns the resource |
| `<org>:component` | free-form | Application or component name |
| `<org>:owner-email` | free-form email | Who to contact |
| `<org>:cost-center` | free-form | Billing chargeback |
| `BackupPlan` | Continuous, Hourly, Daily, Weekly, Monthly | AWS Backup plan selection (must match a configured plan) |
| `Accelerator` | `<AcceleratorPrefix>` | Automatically applied by LZA — don't override |

**Enforcement modes:**
- **Advisory** (no `enforced_for`): tags get reported as compliant/non-compliant; nothing blocked
- **Enforced** (`enforced_for: [<resource types>]`): non-compliant tag operations blocked

**Recommendation:** start advisory-only, then promote keys to enforced once workload teams have aligned conventions. Premature enforcement creates friction.

**Questions to ask:**
- Does the customer have an existing tag taxonomy? Use theirs unless gaps.
- Is cost chargeback a hard requirement? (Drives `cost-center` enforcement timing)
- Are workloads pulling tags from IaC (Terraform/CDK)? Confirm those values match the policy.

**Record:**
```
Tag policy:
  Enforcement: advisory / enforced (per-key)
  Keys: <list with allowed values>
  Cost allocation tags to activate in Billing: <list>
```

---

## Output: the planning document

When all 8 decisions are complete, write a single planning document at the customer repo root:

**File:** `<customer>-lza-plan.md`

**Template:**
```markdown
# <Customer> AWS Landing Zone Plan

> Decisions captured before the first LZA deployment. Source of truth for all downstream config.
> Created: <date>
> Authored by: <engineer>

## 1. AcceleratorPrefix
- Value: <prefix>
- Rationale: <reason>

## 2. Region strategy
- HomeRegion: <region>
- EnabledRegions: [...]
- Opt-in regions used: yes/no

## 3. OU structure
<tree>

## 4. Accounts
<table: Name | OU | Email>

## 5. CIDR plan
- Regional pool: <CIDR>
- Per-VPC table: ...
- (Detailed allocations in `network-cidr-plan.md`)

## 6. IAM Identity Center
- Identity source: ...
- Permission sets: ...

## 7. Compliance
- Standards: ...
- In-scope OUs/accounts: ...

## 8. Tagging
- Tag policy: ...
- Cost allocation tags: ...

## Open items & discrepancies
<table: # | Item | Status / action — one row per unresolved field or per conflict found while
 reconciling the intake form against the design spreadsheet. Mark each Resolved / FOLLOW-UP.
 Close the irreversible ones (region, prefix, CIDR base, emails) before /lza-bootstrap sign-off.>

## Approvals
- Customer sign-off: <date, name>
- NBS sign-off: <date, name>
```

**Get customer sign-off on this document before proceeding to `/lza-bootstrap`.** Trying to relitigate these decisions during deployment is the single biggest source of project delay.

If the customer wants the plan as a Word document to sign, render it with the same generator used for the intake form:

```bash
python3 intake/make_docx.py <customer>-lza-plan.md --customer "<Customer>"
# → <Customer>_AWS_LZA_Plan.docx
```

---

## When to re-invoke this skill

- New customer engagement → fresh `/lza-plan`
- Major customer change (acquisition, compliance shift, region expansion) → re-invoke for the affected sections only
- New region rollout → re-run Decisions 2, 5, 7

## Related skills

- After this: `/lza-bootstrap` — apply the plan's prerequisites to AWS
- Then: `/lza-configure` — translate the plan into YAML
- Then: `/lza-deploy` — run the pipeline
- After deploy: `/lza-validate`, `/lza-add-account`
- Anytime trouble: `/lza-troubleshoot`
