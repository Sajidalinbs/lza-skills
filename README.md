# lza-skills

A modular set of **Claude Code skills** that guide a practitioner through an end-to-end
**AWS Landing Zone Accelerator (LZA)** deployment for a customer engagement — plus the
intake tooling that turns customer requirements into config-ready YAML and a review Excel.

Built from operational experience deploying LZA into real customer organizations.

> **Reference LZA version:** 1.15.0 — compatible with the
> [awslabs/landing-zone-accelerator-on-aws](https://github.com/awslabs/landing-zone-accelerator-on-aws)
> engine and the [aws/lza-universal-configuration](https://github.com/aws/lza-universal-configuration) baseline.

---

## ⚠️ Before you commit / push

This repo is **safe to publish** — it contains playbooks and generic tooling only. Keep it that way:

- **Never commit customer data.** Real account emails, account IDs, and CIDRs belong in a
  separate, private location — not here. The `.gitignore` already excludes
  `*AWS Account and VPC design.xlsx`, any `requirements.<customer>.yaml`, and per-customer
  generated plans. Double-check `git status` before your first push.
- The only network artifacts committed are the **generic** `intake/default-network-plan.*`
  (customer = `customer`, emails = `example.com`).

---

## The skills

| # | Skill | When to invoke | What it covers |
|---|---|---|---|
| 1 | [`lza-plan`](1-lza-plan/SKILL.md) | Start of a new engagement | 8 opinionated decisions: prefix, regions, OU/account design, **proposed default network (VPCs+subnets+CIDRs)**, SSO, compliance, tagging |
| 2 | [`lza-bootstrap`](2-lza-bootstrap/SKILL.md) | First-time AWS Org setup | Mgmt-account checks, Organizations trusted-services audit, break-glass, quotas, Control Tower decision, IAM Identity Center, **GitHub CodeConnections + token prerequisites**, installer CloudFormation |
| 3 | [`lza-configure`](3-lza-configure/SKILL.md) | Filling the config | **Start from the AWS baseline**, then customize every YAML (replacements, accounts, organization, global, security, network, iam, customizations) with per-file pitfalls |
| 4 | [`lza-deploy`](4-lza-deploy/SKILL.md) | Running the pipeline | Stage map, timings, stuck-vs-failing, restart/recovery, cost-during-deploy |
| 5 | [`lza-validate`](5-lza-validate/SKILL.md) | After a green run | CT health, SCP/tag/backup audit, security delegated-admin, network, central logging, **hands-on connectivity tests** |
| 6 | [`lza-add-account`](6-lza-add-account/SKILL.md) | Day-2: new workload account | accounts/network edits, SCP propagation, quarantine release, gotchas |
| 7 | [`lza-troubleshoot`](7-lza-troubleshoot/SKILL.md) | Pipeline failed (cross-cutting, anytime) | 3-API diagnostic flow, Symptom→Cause→Fix table, **bundled fix scripts** |

Each skill folder has a short `README.md` (for GitHub browsing) and the authoritative
**`SKILL.md`** (the full playbook Claude Code loads).

---

## How the skills relate

```
┌───────────────────────────────────────────────────────────────────┐
│  Phase 1 — PLAN        /lza-plan        (opinionated; propose defaults)
│  Phase 2 — BOOTSTRAP   /lza-bootstrap   (org prerequisites + installer)
│  Phase 3 — CONFIGURE   /lza-configure   (baseline + intake → YAML)
│  Phase 4 — DEPLOY      /lza-deploy ─────┐
│                                         ▼
│  Phase 5 — VALIDATE    /lza-validate
│  Phase 6 — OPERATE     /lza-add-account (day-2)
│
│  Cross-cutting:        /lza-troubleshoot (anytime)
└───────────────────────────────────────────────────────────────────┘
```

The natural flow above produces the cleanest deployment, but skills can be invoked independently.

---

## Intake tooling (`intake/`)

The bridge from **customer requirements** to **config-ready YAML + a review Excel**.

```
fetch_baseline.sh  →  config repo seeded from the official AWS baseline (org/security/policies)
requirements.*.yaml → plan_subnets.py → review .xlsx/.csv + accounts/organization/network YAML
        +                    │                 (CIDRs sized per IP count, overlap-checked vs on-prem)
  on-prem CIDRs ─────────────┘
```

- **Opinionated default**: [`intake/requirements.default.yaml`](intake/requirements.default.yaml) ships a full proposed
  network (hub VPCs + Prod/Dev/Test spokes, base `10.240.0.0/13`). Edit only emails + on-prem
  CIDRs; the customer approves the generated review sheet.
- **Pre-generated proposal**: [`intake/default-network-plan.csv`](intake/default-network-plan.csv) (+ `.xlsx`) — open it to
  show the customer every baseline VPC/subnet/CIDR instantly. Generated, never hand-edited.
- **No IPAM, no DNS hub VPC, no central endpoints VPC** — explicit CIDRs; each spoke carries
  its own small `endpoints` tier.

See [`intake/README.md`](intake/README.md) for full usage.

---

## Installing the skills

Claude Code loads skills from `~/.claude/skills/<name>/SKILL.md` (global) or
`<project>/.claude/skills/<name>/SKILL.md` (project-local). To install globally via symlink:

```bash
mkdir -p ~/.claude/skills
# folders are numbered for flow order (1-lza-plan …); symlink them under clean
# names so invocation stays /lza-plan, /lza-bootstrap, etc.
for d in [1-9]-lza-*; do
  ln -snf "$PWD/$d" "$HOME/.claude/skills/${d#*-}"
done
ls -la ~/.claude/skills/ | grep lza-     # verify
```

Symlinks let you keep editing here while Claude Code uses the latest content. Invoke any skill
in a session with a slash, e.g. `/lza-plan`. (A new session is needed to pick up newly-added skills.)

Prerequisites for the intake tooling: `python3`, `openpyxl`, `pyyaml`, `git` (for `fetch_baseline.sh`).

---

## On the AWS LZA MCP Server

AWS ships an [LZA MCP Server](https://github.com/awslabs/lza-mcp-server) that can configure,
deploy, and diagnose an **already-deployed** LZA (and merge the Universal Configuration). It's
**complementary** to these skills — but note: it requires an existing deployment, supports
**S3-based config only** (not CodeConnections/Git), and shares AWS API responses with the AI
provider. These skills remain the path for **planning + bootstrap** (which the MCP can't do) and
for a **Git/CodeConnections** config workflow. See `/lza-configure` for details.

---

## Maintenance & contributing

This skill set is **static markdown + scripts** — it does not auto-update with new LZA releases.
The reference version is recorded at the top of this file and in each `SKILL.md`. When AWS changes
defaults, refresh the affected content. For new field failure modes, add them to
[`lza-troubleshoot/SKILL.md`](7-lza-troubleshoot/SKILL.md) under "Symptom → Root cause → Fix".

---

## License / attribution

Operational playbooks distilled from working with the
[AWS LZA solution](https://aws.amazon.com/solutions/implementations/landing-zone-accelerator-on-aws/).
They reference AWS-published documentation and config patterns but are independent guidance.
