# `/lza-troubleshoot`

> 📖 **Full playbook:** [`SKILL.md`](SKILL.md) — this README is a summary for browsing.

Diagnostic playbook for when an LZA pipeline run fails or behaves unexpectedly. LZA errors are
generic (`Baseline operation FAILED`); this gets you to the real root cause and a fix.

- **Invoke:** anytime — not tied to a deployment phase.

### What it covers
The **3-API diagnostic flow** (baseline operation → StackSet instances → CloudTrail
`PrecheckOrganizationalUnit`) · a **Symptom → Root cause → Fix** table (stacksets-exec SCP deny,
orphan `AWSControlTowerExecution` role, `MISSING_PERMISSIONS_AF_PRODUCT`, SSO trusted-access
trap, Organizations eventual-consistency, OU-rename CFN logical-ID conflict) · deep-dive runbooks.

### Bundled scripts ([`scripts/`](scripts/))
| Script | Purpose |
|---|---|
| `patch_scps.py` | Add `stacksets-exec-*` exemption to SCP **source** files |
| `patch_deployed_scps.py` | Patch **deployed** SCP content via Organizations `update-policy` |
| `find_precheck_failure.sh` | CloudTrail lookup for the pre-check failure event |
| `delete_orphan_ct_role.sh` | Clean up an orphan `AWSControlTowerExecution` role |

> Read each script before running — they modify SCPs and IAM. Dry-run flags provided where destructive.
