---
name: lza-add-account
description: Use as a day-2 operation when the customer asks for a new workload account in an already-deployed LZA. Walks through adding the account to accounts-config.yaml, allocating a VPC and CIDR in network-config.yaml, propagating SCPs and tag policies, running the pipeline, and verifying the quarantine SCP gets released. Invoke once per new workload account.
---

# `/lza-add-account` — Adding a workload account after initial deployment

> **Validated against LZA version:** 1.15.0
> **Predecessor skill:** `/lza-validate` (you should have a healthy LZA first)
> **Related:** `/lza-troubleshoot` (the new-account-gets-stuck scenarios)

## Purpose

Day-2 operation. The customer says "we need a new Dev account for team X." This skill is the safe, predictable way to do it without breaking the existing LZA. It's a small, well-understood edit + pipeline run — the risk is entirely in the details (CIDR collisions, missing TGW share targets, quarantine getting stuck).

## How to use this skill

Confirm the LZA is healthy first (`/lza-validate` green — especially CT `IN_SYNC`). Then: plan the account → edit configs → push → watch the pipeline → validate the new account → hand off. Do not batch many accounts blindly: the **~10 accounts/hour** Organizations limit still applies.

---

## 1 — Pre-add planning

Answer before touching YAML (all should trace back to `<customer>-lza-plan.md`):

- [ ] **OU**: `Workloads/Dev`, `Workloads/Prod`, etc.?
- [ ] **Email alias**: globally unique, real inbox (`aws-managers+<purpose>@<domain>`)
- [ ] **VPC needed?** If yes, allocate the **next free `/16`** from the reserved range in `network-cidr-plan.md` — confirm it doesn't overlap any existing VPC or on-prem range
- [ ] **TGW sharing**: is the target OU (`Workloads/<Name>`) already in the TGW `shareTargets`? If not, you must add it (see gotcha)
- [ ] **Special SCPs?** Usually **no** — the account inherits its OU's guardrails. Only deviate if the plan says so

---

## 2 — Config changes

**`accounts-config.yaml`** — add under `workloadAccounts:`:
```yaml
  - name: <customer>-teamx-dev
    email: aws-managers+teamx-dev@<domain>
    organizationalUnit: Workloads/Dev
```

**`network-config.yaml`** — if a VPC is needed, add a `vpcs:` entry using the **Prod pattern** (loadbalancer / private / database / firewall / endpoints / tgw tiers, 3 AZs), with its TGW attachment:
```yaml
  - name: <customer>-teamx-dev
    account: <customer>-teamx-dev
    region: '{{ HomeRegion }}'
    cidrs: ['10.5.0.0/16']            # next free /16 from network-cidr-plan.md
    subnets: [ ... 3-AZ pattern ... ]
    transitGatewayAttachments:
      - { name: teamx-dev-attach, transitGateway: { name: Main-TGW, account: Network },
          routeTableAssociations: [rt-spoke], routeTablePropagations: [rt-spoke] }
```

**`firewall-rules/rules.txt`** — if the new CIDR introduces a new range, update NFW **ipsets** and any east-west Suricata rules so the new VPC's traffic is correctly inspected/allowed.

---

## 3 — Pipeline run

- [ ] Push the changes — the pipeline **auto-triggers** (or `start-pipeline-execution`)
- [ ] Expected stages: **Accounts** (creation + CT enrollment, 10–20 min) → **Bootstrap** → **Deploy** (VPC/TGW/endpoints)
- [ ] Watch the **quarantine SCP attach then release** — LZA attaches it at the start of Accounts and detaches at Finalize. If it stays attached, the run didn't finish cleanly → `/lza-troubleshoot`

---

## 4 — Post-add validation

- [ ] Account is **ACTIVE** in Organizations
- [ ] Account is **enrolled in CT** (CT console → Accounts)
- [ ] **Inherited SCPs attached** (parent OU's guardrails propagated)
- [ ] **Quarantine SCP detached** (the clean-finish signal)
- [ ] If VPC: **TGW attachment present**, routes match design, gateway + interface endpoints present
- [ ] **AWS Config recorder running** in the new account
- [ ] Account appears in **GuardDuty / Security Hub** member lists

Run the relevant `/lza-validate` hands-on tests scoped to the new account (SSM into a private-subnet EC2; egress; east-west to SharedServices).

---

## 5 — Common gotchas (full diagnostics in `/lza-troubleshoot`)

| Gotcha | What happens | Fix |
|---|---|---|
| Pipeline fails **before Finalize** | New account stuck mid-quarantine (deny-all SCP still attached) | Fix root cause, re-run; SCP releases at Finalize |
| **CIDR collision** | Planned range overlaps an existing TGW route → deploy fails / no routing | Pick the next clean `/16`; never reuse |
| **OU missing from TGW `shareTargets`** | New VPC gets a TGW attachment with **no peer route** (silent — pings just fail) | Add `Workloads/<OU>` to TGW `shareTargets`, re-run |
| **Orphan `AWSControlTowerExecution` role** | "role already exists" from a prior failed attempt | Assume in, detach `AdministratorAccess`, delete; let CT recreate |
| **Account Factory portfolio role missing** | `MISSING_PERMISSIONS_AF_PRODUCT` pre-check (common after CT redeploy) | `associate-principal-with-portfolio` for the pipeline role |

---

## 6 — Customer handoff

Deliver to the customer:
- [ ] New **account ID** and root email
- [ ] **SSO permission sets** assigned (if their users need access)
- [ ] **VPC / subnet IDs** for their IaC
- [ ] **Cost-allocation tag values** pre-applied (`nsf:client`, `nsf:env`, etc.)

---

## When to re-invoke this skill

- Once per new workload account.
- For a **batch** of accounts → repeat, but respect the ~10/hour limit and stagger if needed.
- Not for mandatory/shared accounts — those belong to `/lza-bootstrap`.

## Related skills

- Before: `/lza-validate` — confirm the LZA is healthy before adding to it
- Config detail: `/lza-configure` — full field reference for accounts/network
- Running it: `/lza-deploy` — the stage map for the run this triggers
- When the new account sticks: `/lza-troubleshoot`
