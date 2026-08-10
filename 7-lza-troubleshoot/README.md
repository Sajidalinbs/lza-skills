# `/lza-troubleshoot`

> 📖 **Full playbook:** [`SKILL.md`](SKILL.md) — this README is a summary for browsing.

Diagnostic playbook for when an LZA pipeline run fails or behaves unexpectedly. LZA surfaces
generic errors (`Baseline operation FAILED`) that name neither the resource nor the cause — this
gets you to the real root cause and the fix.

| | |
|---|---|
| **Invoke** | At the moment of a failure — not tied to a deployment phase |
| **Pairs with** | [`/lza-deploy`](../4-lza-deploy/) · [`/lza-add-account`](../6-lza-add-account/) |
| **Not for** | Security Hub *findings* — use [`/lza-security-remediate`](../8-lza-security-remediate/) |

### What it covers

The **3-API diagnostic flow** (baseline operation → StackSet instances → CloudTrail
`PrecheckOrganizationalUnit`), then a **Symptom → Root cause → Fix** table with deep-dive
runbooks for each:

- `stacksets-exec` SCP deny blocking Account Factory
- Orphan `AWSControlTowerExecution` role from a partially-failed deploy
- `MISSING_PERMISSIONS_AF_PRODUCT` pre-check failure
- IAM Identity Center trusted-access / takeover trap
- Organizations API eventual consistency
- OU **rename** → CloudFormation logical-ID conflict (`already exists in stack`)
- OU **delete** → `ValidateEnvironmentConfig` orphan-OU failure

### Bundled scripts ([`scripts/`](scripts/))

| Script | Purpose |
|---|---|
| `patch_scps.py` | Add the `stacksets-exec-*` exemption to SCP **source** files |
| `patch_deployed_scps.py` | Patch **deployed** SCP content via Organizations `update-policy` |
| `find_precheck_failure.sh` | CloudTrail lookup for the pre-check failure event |
| `delete_orphan_ct_role.sh` | Clean up an orphan `AWSControlTowerExecution` role |
| `cleanup_empty_ous.py` | Disable CT controls/baseline and delete emptied OUs, in the required order |

> ⚠️ Read each script before running it — they modify SCPs, IAM, and OUs. Dry-run flags are
> provided where the action is destructive.
