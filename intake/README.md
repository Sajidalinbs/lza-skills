# Intake tooling

The bridge between **what the customer tells you** and **what LZA needs** — a requirements
document to send out, and a planner that turns the answers into an overlap-checked IP design
plus config-ready YAML.

```
       ┌─ send ──────────────────────────────────────────────────────────────┐
       │  lza-intake-form.md ──make_docx.py──► <Customer>_AWS_LZA_Intake.docx│
       └──────────────────────────────────────────────────┬──────────────────┘
                                                          │ customer returns answers
                                                          ▼
  requirements.<customer>.yaml ──┐
  (subnet tiers + IP counts)     ├─► plan_subnets.py ─► <customer>-network-plan.xlsx  (review + sign-off)
  on-prem CIDRs to avoid ────────┘         │            accounts-config.yaml
                                           │            organization-config.yaml
                        (refuses any overlap)            network-config.snippet.yaml

  fetch_baseline.sh ─────────────────────────────────► config repo seeded from the AWS baseline
```

## Files

| File | What it is |
|---|---|
| `lza-intake-form.md` | The **customer-facing requirements document** — 16 fill-in sections (contacts & break-glass, email distribution + notification lists, current AWS state, regions, prefix, OUs, accounts, on-prem CIDR confirmation, DNS & egress, SSO, config repo, compliance, tagging, logging & backup, timeline, sign-off). Send this **first**. |
| `make_docx.py` | Renders any Markdown artifact here as **Word** — the intake form to send out, or `<customer>-lza-plan.md` to sign off. Standard library only: no `python-docx`, no pandoc. |
| `fetch_baseline.sh` | Seeds the config repo from the **official AWS baseline** (LZA Universal Configuration `modules/base/default`) — the 6 YAML files + policy folders. Run this before customizing anything. |
| `requirements.default.yaml` | The **opinionated default** network we propose (hub VPCs + Prod/Dev/Test spokes, base `10.240`). Edit only emails + on-prem CIDRs, run the planner, and have the customer approve the review workbook. **Start here.** |
| `requirements.example.yaml` | A custom-layout example (App A = 10 subnets, App B = 12) for when the default doesn't fit. |
| `plan_subnets.py` | Sizes subnets from IP counts, carves non-overlapping CIDRs, refuses on-prem overlap, writes the review workbook + config YAML. |
| `default-ou-structure.md` | The default OU/account layout (matches the AWS baseline) and how to customize it. |
| `default-network-plan.xlsx` / `.csv` | **Pre-generated** view of the opinionated default (every baseline VPC + subnet + CIDR) — open it to show a customer the proposal instantly. Generated from `requirements.default.yaml`; **never hand-edit — regenerate.** The `.csv` is the git-diff-friendly twin. |

**Generated per customer** (git-ignored — see [Handling customer data](../README.md#handling-customer-data)):
`<customer>-network-plan.xlsx` (review artifact) · `accounts-config.yaml` · `organization-config.yaml`
(OU block) · `network-config.snippet.yaml` (paste into `network-config.yaml`) · `*.docx`.

---

## 1 — Send the requirements document

```bash
python3 make_docx.py lza-intake-form.md --customer "Acme Corp"
# → Acme_Corp_AWS_LZA_Intake.docx
```

`--customer` also substitutes every `<Customer>` / `<customer>` placeholder in the source. The
same generator renders the finished plan for signature:

```bash
python3 make_docx.py ../acme-lza-plan.md --customer "Acme Corp"
# → Acme_Corp_AWS_LZA_Plan.docx
```

Two sections drive everything downstream and are worth chasing until they are complete:
**§2 email distribution** (root emails are permanent and globally unique) and **§8 on-prem CIDR
confirmation** (an omitted range means renumbering a VPC later).

---

## 2 — Plan the network

You do **not** hand-write CIDRs. State, per VPC, the **subnet tiers**, **how many IPs each
needs**, and across **which AZs**. Each tier becomes one subnet per AZ:

```yaml
tiers:
  - { name: private,      ips: 8000, route_table: rt-private,  type: Private }   # 3 AZ → 3 subnets, each /19
  - { name: loadbalancer, ips: 1000, route_table: rt-lb,       type: Private }   # 3 AZ → 3 subnets, each /22
  - { name: database,     ips: 1000, route_table: rt-database, type: Private }   # 3 AZ → 3 subnets, each /22
  - { name: tgw,          ips: 8,    route_table: rt-tgw,      type: Transit, azs: [a] }  # 1 subnet, /28
```

- **10 subnets in account A and 12 in account B** is just a different tier/AZ combination per VPC.
- **Sizing is automatic** — the planner picks the smallest prefix whose *usable* host count
  (block size minus the 5 AWS-reserved addresses) covers the IPs you asked for. A large `private`
  tier lands on `/19`; a small `tgw` tier on `/28`.

### On-prem overlap safety

List every range reachable over DX, VPN, or cloud peering under `external_cidrs:` (straight from
§8.1 of the intake form). The planner refuses:

1. a `supernet` that overlaps any of them,
2. any **VPC CIDR** that overlaps them,
3. any **generated subnet** that overlaps them,
4. two VPCs that overlap each other.

On any failure it **errors and writes nothing** — you fix the input before the customer ever
sees a bad plan.

---

## Run it end to end

```bash
# 0) send the requirements document (Word — no extra dependencies)
python3 make_docx.py lza-intake-form.md --customer "Acme Corp"

# 1) seed the config repo from the official AWS baseline (org / security / governance + policies)
./fetch_baseline.sh ../acme-lza-config       # base only; network comes from intake

# 2) plan the network and emit config fragments
pip install openpyxl pyyaml                  # one-time
python3 plan_subnets.py requirements.acme.yaml
# → acme-network-plan.xlsx          (customer reviews and approves)
#   accounts-config.yaml            (ready to commit)
#   organization-config.yaml        (OU block)
#   network-config.snippet.yaml     (paste into network-config.yaml)
```

## Where it fits in the skill flow

| Step | Skill | What this tooling provides |
|---|---|---|
| Before the planning session | [`/lza-plan`](../1-lza-plan/) Mode A | `lza-intake-form.md` rendered to `.docx` — its answers feed all 8 decisions (mapping table in the form's §16) |
| Decisions 4 & 5 | [`/lza-plan`](../1-lza-plan/) | The review workbook **is** the artifact those decisions produce |
| Step 0 and beyond | [`/lza-configure`](../3-lza-configure/) | `fetch_baseline.sh` seeds the repo; one planner run emits `accounts-config.yaml` and `organization-config.yaml` ready to commit (add SCP/tag/backup policy blocks per the skill), and `network-config.snippet.yaml` drops into `network-config.yaml` |

## Requirements

`python3` · `openpyxl` and `pyyaml` (planner only) · `git` (for `fetch_baseline.sh`).
`make_docx.py` needs nothing beyond the standard library.
