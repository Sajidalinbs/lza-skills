# `/lza-plan`

> 📖 **Full playbook:** [`SKILL.md`](SKILL.md) — this README is a summary for browsing.

Pre-deployment planning for a **new** LZA customer engagement. Answers the irreversible
questions *before* any YAML is written, and produces `<customer>-lza-plan.md` — the single
source of truth for every downstream skill.

- **Invoke:** once per new customer, at the very start.
- **Predecessor:** none (this is where you start) · **Successor:** [`/lza-bootstrap`](../2-lza-bootstrap/)

### The 8 decisions (opinionated — propose a default, customer confirms)
1. AcceleratorPrefix · 2. Region strategy · 3. OU structure · 4. Account inventory ·
5. **CIDR / network plan** (proposes a full default network; one on-prem overlap check) ·
6. IAM Identity Center · 7. Compliance scope · 8. Tagging

The network decision uses the [`intake/`](../intake/) tooling to generate an overlap-checked,
customer-reviewable CIDR plan.
