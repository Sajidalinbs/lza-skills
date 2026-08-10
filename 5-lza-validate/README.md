# `/lza-validate`

> 📖 **Full playbook:** [`SKILL.md`](SKILL.md) — this README is a summary for browsing.

Prove a green pipeline actually produced a healthy landing zone. *"Pipeline went green"* is not
the same as *"the deployment is correct"* — this skill checks the difference.

| | |
|---|---|
| **Invoke** | Immediately after the pipeline reaches Finalize, then on a cadence (weekly/monthly) |
| **Predecessor** | [`/lza-deploy`](../4-lza-deploy/) |
| **Successor** | [`/lza-add-account`](../6-lza-add-account/) (day-2) |
| **Produces** | A customer-facing validation report |

### What it covers

Control Tower health and drift · SCP / RCP / tag-policy / backup-policy attachment audit ·
security-services delegated admin in the Audit account · TGW sharing and routing · central
logging pipeline · AWS Config aggregator · IAM Identity Center · **hands-on tests** — SSM into a
private subnet, internet egress, east-west connectivity, Security Hub aggregation.

Findings that turn out to be Security Hub noise → [`/lza-security-remediate`](../8-lza-security-remediate/).

### Bundled tooling

[`test-infra/`](test-infra/) — a throwaway Terraform stack that proves the ingress and egress
paths work end to end through the central Network Firewall (~19 resources, ~$1.50/day). Apply,
run two checks, destroy.
