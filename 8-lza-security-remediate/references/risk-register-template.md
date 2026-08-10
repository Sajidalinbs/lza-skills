# <Customer> LZA — Security Hub Suppression & Exception Risk Register

> Working document. Decide with the customer whether it lives in the config repo (versioned) or
> outside it. **Last updated:** <DATE> · **Delegated security admin (Audit):** <AUDIT_ACCT> ·
> **HomeRegion:** <REGION>
> **Prefix note:** config `{{ AcceleratorPrefix }}` = `<prefix>`; LZA framework resources use
> `<framework-prefix>` (often the default `AWSAccelerator`). Suppression rules must match BOTH.

## 1. Summary

| Category | Count |
|---|---|
| Suppression rules — pre-existing | |
| Suppression rules — added | |
| Existing rules corrected (prefix/tag) | |
| Operational changes (Inspector, etc.) | |
| Open customer decisions | |

## 2. Suppression rules

### 2.1 By-design LZA framework noise (low residual risk)
| # | Control | Rule name | Scope / match | Rationale | Residual risk |
|---|---|---|---|---|---|
| | StepFunctions.1 | | `ResourceId ~ CreateOrganizationAccounts` | LZA CDK provider waiter | Low |
| | CloudWatch.15 | | `*FailedAlarm` | LZA pipeline alarm | Low |
| | Lambda.3/7, Kinesis.3, DynamoDB.4/6, KMS.1/2 | | LZA resources (both prefixes) | LZA-managed | Low |
| | S3.6/7/9/11/15/17/20 | | `aws-accelerator-*`, `cdk-accel-assets` (name only) | LZA/CDK buckets | Low–Med |

### 2.2 Documented exceptions (real risk, accepted — review on cadence)
| # | Control | Scope | Rationale | Residual | Compensating control |
|---|---|---|---|---|---|
| | IAM.21 | `policy/<Customer>-*` | service-wildcard permission-set policies by design | Med | PermissionsBoundary on every write permission set |
| | IAM.22 | break-glass users | dormant by design (SEC03-BP03) | Med | quarterly drill + tamper SCP + activity alerts |
| | Backup.1 | Management/Audit/LogArchive | core accounts, no workloads | Low | org backup policy covers Infra + Workloads |

## 3. Prefix/tag correction applied
Root cause + which rules were changed to match both `<prefix>` and `<framework-prefix>`; which S3
rules had the tag filter dropped. ⚠️ Not retroactive — existing NEW findings need a bulk flip.

## 4. Operational changes (not suppressions)
| Date | Change | Detail | Owner | Reversibility / cost / drift |
|---|---|---|---|---|
| <DATE> | Amazon Inspector enabled org-wide | delegated admin = Audit; EC2/ECR/Lambda/Lambda-code; auto-enable on | Security | Reversible; billable; CLI (NOT IaC — LZA unsupported), re-apply if org rebuilt |

## 5. Findings reviewed — NOT accelerator-related (fix or accept)
| Finding | Verdict | Recommended action | Status |
|---|---|---|---|
| CloudTrail `<trail>` log-file validation off | manual trail | enable validation / delete | Open |
| IAM user `<name>` no MFA | human/manual | enable MFA / delete | Open |
| `cf-templates-*` versioning off | console bucket | enable versioning / delete | Open |
| "No Network Firewall" in non-inspection accounts | by design | suppress / accept | Open |

## 6. CIS section-4 monitoring
Option chosen (A deploy filters / B disable). If A: 15 metric filters + 15 alarms on `<CT_LOG_GROUP>`
→ Management/HomeRegion → SecurityHigh/Medium SNS. Note whether CloudWatch.1–14 were re-enabled in
Security Hub (needed for native-SH PASS; enable in Management only).

## 7. Open decisions pending customer
1.
2.

## 8. Verification / audit trail
Date, who, what was confirmed live (per-control SUPPRESSED/NEW counts; Inspector status; etc.).
Reminder: config changes take effect only after the pipeline redeploys, and are not retroactive.
