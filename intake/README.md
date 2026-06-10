# LZA Intake → CIDR Plan → Review Excel

The bridge between **customer requirements** and **LZA config**. The engineer fills one
small YAML; the planner decides the actual IP layout (avoiding on-prem), and produces an
Excel for the customer to review **before** any YAML is written.

```
 customer requirements                         review + sign-off          LZA config
 (subnet names + IP counts) ─► plan_subnets.py ─► <customer>-network-plan.xlsx ─► network-config.yaml
            +                        │                                          (via network-config.snippet.yaml)
   on-prem CIDRs to avoid ───────────┘
```

## Files

| File | What it is |
|---|---|
| `fetch_baseline.sh` | Seeds the config repo from the **official AWS baseline** (LZA Universal Configuration `modules/base/default`) — the 6 YAML + policy folders. Run this FIRST. |
| `requirements.default.yaml` | The **opinionated default** network we propose to a customer (hub VPCs + Prod/Dev/Test spokes, base `10.240`). Edit only emails + on-prem CIDRs, run it, and the customer approves the review Excel. Start here. |
| `requirements.example.yaml` | A custom-layout example (App A = 10 subnets, App B = 12) for when the default doesn't fit. |
| `plan_subnets.py` | Sizes subnets from IP counts, carves non-overlapping CIDRs, refuses on-prem overlap, writes the review workbook + YAML snippet. |
| `default-ou-structure.md` | The default OU/account layout (matches the AWS baseline) + how to customize. |
| `default-network-plan.xlsx` / `.csv` | **Pre-generated** view of the opinionated default (every baseline VPC + subnet + CIDR) — open it to show the customer the proposal instantly. **Generated from `requirements.default.yaml` — never hand-edit; regenerate** (`plan_subnets.py requirements.default.yaml`). The `.csv` is the git-diff-friendly twin. |
| `<customer>-network-plan.xlsx` | **Output** — review artifact (Accounts / OUs / VPCs / Subnets / External-CIDRs). |
| `accounts-config.yaml` | **Output** — ready-to-use LZA accounts config (mandatory + workload). |
| `organization-config.yaml` | **Output** — LZA OU block (SCP/tag/backup policies added later in `/lza-configure`). |
| `network-config.snippet.yaml` | **Output** — `vpcs[].subnets[]` block; paste into `network-config.yaml`. |

## The intake model (answers "10 vs 12 subnets")

You do **not** hand-write CIDRs. You state, per VPC, the **subnet tiers**, **how many IPs
each needs**, and across **which AZs**. Each tier becomes one subnet per AZ:

```yaml
tiers:
  - { name: private,      ips: 8000, route_table: rt-private,  type: Private }   # 3 AZ → 3 subnets, each /19
  - { name: loadbalancer, ips: 1000, route_table: rt-lb,       type: Private }   # 3 AZ → 3 subnets, each /22
  - { name: database,     ips: 1000, route_table: rt-database, type: Private }   # 3 AZ → 3 subnets, each /22
  - { name: tgw,          ips: 8,    route_table: rt-tgw,       type: Transit, azs: [a] }  # 1 subnet, /28
```

- **10 subnets in account A, 12 in account B** = just different tier/AZ combinations per VPC.
- **Different sizes per tier** is automatic: the planner picks the smallest prefix whose
  *usable* host count (block size − 5 AWS-reserved) ≥ the IPs you asked for. A big `private`
  tier lands on `/19`; a tiny `tgw` tier on `/28`.

## On-prem overlap safety

List every range reachable over DX / VPN / cloud-peering under `external_cidrs:`. The planner:
1. refuses a `supernet` that overlaps any of them,
2. refuses any **VPC CIDR** that overlaps them,
3. refuses any **generated subnet** that overlaps them,
4. refuses two VPCs that overlap each other.

If any check fails it **errors and writes nothing** — you fix the input before the customer ever sees a bad plan.

## Run it

```bash
# 0) seed the config repo from the official AWS baseline (org/security/governance + policies)
./fetch_baseline.sh ../acme-lza-config        # base only; network from intake (no IPAM/DNS/endpoints VPC)

# 1) plan the network + emit config fragments
pip install openpyxl pyyaml          # one-time
python3 plan_subnets.py requirements.example.yaml
# → acme-network-plan.xlsx            (review)
#   accounts-config.yaml              (ready)
#   organization-config.yaml          (OU block)
#   network-config.snippet.yaml       (paste into network-config.yaml)
```

## Where it fits in the skill flow

- `/lza-plan` Decision 4 (accounts) + Decision 5 (CIDR) — this workbook **is** the artifact those decisions produce.
- `/lza-configure` — one run emits three of the config files directly: `accounts-config.yaml`
  and `organization-config.yaml` are ready to commit (add SCP/tag/backup policy blocks per
  `/lza-configure`); `network-config.snippet.yaml` drops into `network-config.yaml`.
