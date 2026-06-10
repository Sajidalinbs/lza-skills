# `/lza-add-account`

> 📖 **Full playbook:** [`SKILL.md`](SKILL.md) — this README is a summary for browsing.

Day-2 operation: add a new workload account to an already-deployed, healthy LZA without
breaking it.

- **Invoke:** once per new workload account.
- **Predecessor:** [`/lza-validate`](../lza-validate/) (have a healthy LZA first) ·
  **Related:** [`/lza-troubleshoot`](../lza-troubleshoot/)

### What it covers
Pre-add planning (OU, email, CIDR from the reserved range, TGW sharing) · config edits to
`accounts-config.yaml` + `network-config.yaml` · the pipeline run · post-add validation ·
common gotchas (CIDR collision, missing TGW `shareTargets`, quarantine stuck, orphan CT role) ·
customer handoff.
