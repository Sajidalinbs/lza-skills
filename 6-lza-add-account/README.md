# `/lza-add-account`

> 📖 **Full playbook:** [`SKILL.md`](SKILL.md) — this README is a summary for browsing.

Day-2 operation: add a new workload account to an already-deployed, healthy LZA without breaking
it.

| | |
|---|---|
| **Invoke** | Once per new workload account |
| **Prerequisite** | A healthy landing zone — run [`/lza-validate`](../5-lza-validate/) first |
| **Related** | [`/lza-troubleshoot`](../7-lza-troubleshoot/) if the pipeline run fails |

### What it covers

Pre-add planning (OU placement, account email, a CIDR from the reserved range, TGW sharing) ·
config edits to `accounts-config.yaml` and `network-config.yaml` · the pipeline run and what it
does per stage · post-add validation · customer handoff.

### Common gotchas it catches

CIDR collision with an existing spoke · missing TGW `shareTargets` (the account deploys but has
no connectivity) · the quarantine SCP never being released · an orphan
`AWSControlTowerExecution` role left by a partially-failed run · hitting the ~10 accounts/hour
Organizations creation limit.
