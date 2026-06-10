# `/lza-deploy`

> 📖 **Full playbook:** [`SKILL.md`](SKILL.md) — this README is a summary for browsing.

Run the `AWSAccelerator-Pipeline` end-to-end and know what's normal vs broken.

- **Invoke:** when triggering the pipeline or watching a run.
- **Predecessor:** [`/lza-configure`](../3-lza-configure/) · **Successor:** [`/lza-validate`](../5-lza-validate/)

### What it covers
Full pipeline **stage map** (Source → Prepare → Accounts → Bootstrap → … → Finalize) with
typical durations and common failures · what **success** looks like · **stuck vs failing**
thresholds · **restart & recovery** (idempotent re-run, no-op commit, skip flags) · monitoring
commands · **cost during deploy** (NAT/Network Firewall start billing at the Deploy stage).
On any failure → [`/lza-troubleshoot`](../7-lza-troubleshoot/).
