# `/lza-deploy`

> 📖 **Full playbook:** [`SKILL.md`](SKILL.md) — this README is a summary for browsing.

Run the `AWSAccelerator-Pipeline` end to end and know what is normal versus broken. A first full
deployment is measured in hours, and long silences are usually expected — this skill tells you
which ones aren't.

| | |
|---|---|
| **Invoke** | When triggering the pipeline, or while watching a run |
| **Predecessor** | [`/lza-configure`](../3-lza-configure/) |
| **Successor** | [`/lza-validate`](../5-lza-validate/) |
| **On failure** | [`/lza-troubleshoot`](../7-lza-troubleshoot/) |

### What it covers

Full pipeline **stage map** (Source → Prepare → Accounts → Bootstrap → … → Finalize) with typical
durations and the failures common to each · what **success** actually looks like per stage ·
**stuck vs failing** thresholds · **restart and recovery** (idempotent re-runs, no-op commits,
skip flags) · monitoring commands · **cost during deploy** — NAT gateways and Network Firewall
start billing at the Deploy stage, not at Finalize.
