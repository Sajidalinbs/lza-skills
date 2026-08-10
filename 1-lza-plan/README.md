# `/lza-plan`

> 📖 **Full playbook:** [`SKILL.md`](SKILL.md) — this README is a summary for browsing.

Pre-deployment planning for a **new** LZA customer engagement. Answers the irreversible
questions *before* any YAML is written and produces `<customer>-lza-plan.md` — the single source
of truth for every downstream skill.

| | |
|---|---|
| **Invoke** | Once per new customer, at the very start |
| **Predecessor** | None — this is where you start |
| **Successor** | [`/lza-bootstrap`](../2-lza-bootstrap/) |
| **Produces** | `<customer>-lza-plan.md` · `<customer>-network-plan.xlsx` · config-ready YAML fragments |

### The 8 decisions

Opinionated by design — propose a concrete default, the customer confirms or corrects it.

| # | Decision | Reversibility |
|:--:|---|---|
| 1 | `AcceleratorPrefix` | ❌ Fixed at first deploy |
| 2 | Region strategy (`HomeRegion`, enabled regions) | ❌ Home region fixed |
| 3 | OU structure | ❌ Names fixed once controls attach |
| 4 | Account inventory + emails | ❌ Emails are permanent |
| 5 | **CIDR / network plan** | ❌ VPC CIDRs are permanent |
| 6 | IAM Identity Center strategy | ⚠️ Rework is disruptive |
| 7 | Compliance scope | ✅ Adjustable |
| 8 | Tagging strategy | ✅ Adjustable |

### Two modes

- **Mode A — intake-document-first (the normal flow).** Send the customer
  [`intake/lza-intake-form.md`](../intake/lza-intake-form.md) rendered as Word, then ingest and
  reconcile the returned answers rather than interviewing live:
  ```bash
  python3 intake/make_docx.py intake/lza-intake-form.md --customer "<Customer>"
  ```
- **Mode B — live walk-through.** For early scoping calls: walk the 8 decisions in order,
  leading with the recommended default each time.

Decision 5 uses the [`intake/`](../intake/) planner to generate an overlap-checked,
customer-reviewable CIDR plan — it refuses any layout that collides with on-prem.
