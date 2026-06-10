# Default OU & Account Structure

This is the **default** layout the intake assumes. It matches the **AWS LZA Universal
Configuration baseline** (`aws/lza-universal-configuration` → `modules/base/default`), so
the intake-generated `accounts-config.yaml` / `organization-config.yaml` merge cleanly with
the baseline you copy via `fetch_baseline.sh`. The customer only changes it if they ask.

```
Root
├── Security                 ← LogArchive, Audit (mandatory)
├── Infrastructure           ← Network, SharedServices, Perimeter
├── Suspended  (ignore: true)← decommissioned accounts
└── Workloads                ← application workload parent
    ├── Sandbox
    ├── Dev
    ├── Test
    └── Prod
```

| OU Path | Parent | Purpose |
|---|---|---|
| `Security` | Root | Audit + LogArchive only |
| `Infrastructure` | Root | Network / SharedServices / Perimeter |
| `Suspended` | Root | decommissioned accounts (`ignore: true`) |
| `Workloads` | Root | application workload parent (SCPs + tag policy attach here) |
| `Workloads/Sandbox` | Workloads | sandbox accounts |
| `Workloads/Dev` | Workloads | development accounts |
| `Workloads/Test` | Workloads | test accounts |
| `Workloads/Prod` | Workloads | production accounts (AWS Backup policy attached) |

**Baseline accounts that ship with this** (`modules/base/default/accounts-config.yaml`):

| Account | OU | Type |
|---|---|---|
| Management | Root | Mandatory |
| LogArchive | Security | Mandatory |
| Audit | Security | Mandatory |
| Network | Infrastructure | Workload |
| SharedServices | Infrastructure | Workload |
| Perimeter | Infrastructure | Workload |

> **Networking note:** the baseline's *network* modules also define DNS and central
> interface-endpoints VPCs and use IPAM — **we do not use those.** CIDRs are explicit and
> networking comes from the intake planner. Drop the AWS network module's IPAM / DNS-VPC /
> endpoints-VPC blocks if you copy one for reference.

## How to customize (example)

For **business-unit-first** instead of environment-first, edit the `ous:` block in
`requirements.<customer>.yaml`:

```yaml
ous:
  - { path: Root,                 parent: "-",        purpose: root }
  - { path: Security,             parent: Root,       purpose: Audit + LogArchive }
  - { path: Infrastructure,       parent: Root,       purpose: shared infra }
  - { path: Suspended,            parent: Root,       purpose: decommissioned, ignore: true }
  - { path: Workloads,            parent: Root,       purpose: workload parent }
  - { path: Workloads/TeamA,      parent: Workloads,  purpose: Team A }
  - { path: Workloads/TeamA/Prod, parent: Workloads/TeamA, purpose: Team A prod }
  - { path: Workloads/TeamA/Dev,  parent: Workloads/TeamA, purpose: Team A dev }
  - { path: Workloads/TeamB,      parent: Workloads,  purpose: Team B }
  - { path: Workloads/TeamB/Prod, parent: Workloads/TeamB, purpose: Team B prod }
```

Each account's `ou:` must reference one of these paths — the planner validates that every
account's OU exists in the `ous:` list.

> Compliance-scoped variant (PCI / HIPAA): add a dedicated OU (e.g. `Workloads/PCI`)
> so its accounts get stricter SCPs — see `/lza-plan` Decision 3 and Decision 7.
