# `/lza-bootstrap`

> 📖 **Full playbook:** [`SKILL.md`](SKILL.md) — this README is a summary for browsing.

Prepare the AWS Organization and install the accelerator, after `/lza-plan` is signed off.
Leaves you with a running (config-empty) `AWSAccelerator-Pipeline`, ready for `/lza-configure`.

| | |
|---|---|
| **Invoke** | Once per AWS Organization, before any real config is deployed |
| **Predecessor** | [`/lza-plan`](../1-lza-plan/) |
| **Successor** | [`/lza-configure`](../3-lza-configure/) |
| **Gate** | The signed-off plan — all 8 decisions recorded, irreversible items closed |

### What it covers

Management-account verification · AWS credential preflight · Organizations trusted-services
audit (the IAM Identity Center takeover trap) · break-glass access · service quotas (CodeBuild
concurrency ≥ 3) · shared-account emails · opt-in regions · the **Control Tower decision**
(standalone CT recommended over LZA-bootstrapped) · IAM Identity Center strategy · the
**config-source decision** (CodeCommit is deprecated) including the **GitHub CodeConnections
org-owner procedure** and the `accelerator/github-token` Secrets Manager prerequisite · the
installer CloudFormation stack and its first (CDK-bootstrap) pipeline run.

> ⚠️ The `AcceleratorPrefix` entered on the installer stack must match `replacements-config.yaml`
> exactly. A mismatch is the single most common silent failure — both values lock after the
> first run.
