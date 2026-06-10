# `/lza-validate`

> 📖 **Full playbook:** [`SKILL.md`](SKILL.md) — this README is a summary for browsing.

Prove a green pipeline actually produced a healthy landing zone. "Pipeline went green" ≠
"deployment is correct."

- **Invoke:** immediately after the pipeline reaches Finalize, and on a cadence (weekly/monthly).
- **Predecessor:** [`/lza-deploy`](../4-lza-deploy/) · **Successor:** [`/lza-add-account`](../6-lza-add-account/) (day-2)

### What it covers
Control Tower health & drift · SCP/RCP/tag/backup attachment audit · security-services
delegated admin (Audit account) · TGW sharing & routing · central logging · IAM Identity Center ·
**hands-on tests** (SSM into a private subnet, egress, east-west, Security Hub aggregation) ·
a customer-facing validation report.
