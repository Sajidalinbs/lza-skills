# `/lza-bootstrap`

> 📖 **Full playbook:** [`SKILL.md`](SKILL.md) — this README is a summary for browsing.

Prepare the AWS Organization and install the accelerator, after `/lza-plan` is signed off.
Leaves you with a running (config-empty) `AWSAccelerator-Pipeline`, ready for `/lza-configure`.

- **Invoke:** once per AWS Organization, before any real config is deployed.
- **Predecessor:** [`/lza-plan`](../lza-plan/) · **Successor:** [`/lza-configure`](../lza-configure/)

### What it covers
Management-account verification · Organizations trusted-services audit (the IDC-takeover trap) ·
break-glass access · service quotas (CodeBuild concurrency ≥ 3) · shared-account emails ·
opt-in regions · **Control Tower decision** (standalone CT recommended) · IAM Identity Center
strategy · **config-source decision** (CodeCommit deprecated) including the **GitHub
CodeConnections org-owner procedure** and the **`accelerator/github-token` Secrets Manager**
prerequisite · the installer CloudFormation stack and its first (CDK-bootstrap) pipeline run.
