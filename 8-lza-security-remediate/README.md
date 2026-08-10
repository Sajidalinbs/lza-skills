# `/lza-security-remediate`

> 📖 **Full playbook:** [`SKILL.md`](SKILL.md) — this README is a summary for browsing.

Turn a wall of Security Hub findings into *"everything is passing, suppressed with a documented
reason, or on a tracked risk register."* Handles the common trap where suppression rules were
written but **silently never fire**.

| | |
|---|---|
| **Invoke** | After `/lza-validate` (or a CIS/Prowler scan) surfaces findings; or when new suppression rules don't clear them |
| **Pairs with** | [`/lza-validate`](../5-lza-validate/) — surfaces the findings |
| **Not for** | Pipeline *failures* — use [`/lza-troubleshoot`](../7-lza-troubleshoot/) |
| **Produces** | A suppression risk register the customer can sign |

### What it covers

Audit which suppressions actually fire · the **`{{ AcceleratorPrefix }}` vs `AWSAccelerator`**
mismatch — the number-one reason rules don't fire · finding-level tags arriving `null` and
inconsistent `Accelerator` tag values · classifying findings as LZA-created versus not ·
suppression rules for LZA framework noise (StepFunctions.1, CloudWatch.15, Lambda, Kinesis, KMS,
S3, DynamoDB) · documented exceptions (IAM.21/22, Backup.1) · **CIS section-4 CloudWatch metric
filters and alarms** (Option A deploy / Option B disable) · **Amazon Inspector org-wide**
enablement, which LZA has no native support for · **AWS Backup** plan coverage · and the
"automation rules aren't retroactive" bulk re-flip.

### Bundled tooling

| Path | Purpose |
|---|---|
| `scripts/audit_suppressions.sh` | Compare deployed rule names against real resource ARNs to expose the prefix mismatch |
| `scripts/enable_inspector_org.sh` | Enable Amazon Inspector across the organization |
| `scripts/bulk_suppress.sh` | Re-apply suppression to findings that predate a new rule |
| `references/cis-cloudwatch-block.yaml` | Drop-in CIS section-4 metric filters + alarms |
| `references/risk-register-template.md` | Customer-signable exception register |

> ⚠️ Suppressing a finding is a risk acceptance, not a fix. Every suppression added here belongs
> on the risk register with an owner and a reason.
