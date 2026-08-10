# test-infra — internet ⇄ workload connectivity smoke test

Transient Terraform stack that **proves the ingress and egress paths work end-to-end
through the central Network Firewall** for a workload (staging) account. Apply, run two
checks, then `terraform destroy`. Not production architecture — keep it throwaway.

## What it builds (~19 resources, ~$1.50/day)

| Resource | Account | Purpose |
|---|---|---|
| Public ALB (HTTP:80) | Perimeter (ingress VPC) | Internet front door |
| Cross-account IP target group (HTTPS:443) | Perimeter | Targets the internal ALB IPs across VPCs via TGW (crosses the NFW) |
| Internal ALB (HTTPS:443) + self-signed ACM cert | Workload (loadbalancer subnets) | Receives the cross-firewall leg |
| ECS Fargate: `web` (nginx) + `egress-probe` sidecar | Workload (private subnets) | Ingress backend + egress prober |

## Paths proven

- **Ingress:** `Internet:80 → Public ALB → TGW → NFW → Internal ALB:443 → ECS nginx:80`
- **Egress:** `ECS → 0.0.0.0/0 → TGW → NFW → NAT → Internet`

The public→internal leg is **443** because that's the east-west port the NFW passes in a
tightened policy (an ALB doesn't validate backend certs, so self-signed is fine). Under an
**allow-all** firewall it works too.

## Prerequisites

1. Landing zone fully deployed: VPCs, TGW with `rt-spoke→inspection` / `rt-firewall→egress`,
   NFW `READY`, NAT GWs, `ingress-public→IGW`. (Verify per `/lza-validate` §6.)
2. AWS profiles for the Perimeter + workload accounts (assume-role via mgmt is easiest — see
   `terraform.tfvars.example`).
3. `terraform`, `aws` CLI, `dig`.

## Run

```bash
cp terraform.tfvars.example terraform.tfvars   # set prefix/profiles/names
terraform init && terraform apply
```

## Test

```bash
# INGRESS — expect nginx welcome HTML (503 for first ~60s is normal)
curl -s http://$(terraform output -raw public_alb_dns_name)/ | head

# EGRESS — expect a probe line every 30s
aws logs tail "$(terraform output -raw ecs_log_group)" --log-stream-name-prefix egress \
  --since 5m --follow --profile <staging_profile> --region <region>
```

Egress probe output:
- `amazonaws (ALLOW): HTTP 4xx` → TLS handshake completed = egress path works (the 4xx is the
  AWS endpoint rejecting an empty request — that's fine; it proves reachability).
- `example.com` → **blocked** under a per-SNI allowlist policy, or **HTTP 200** under an
  allow-all policy (both are "expected" depending on the current firewall ruleset).

## Cleanup

```bash
terraform destroy
```

## Adapting to a customer

Only `terraform.tfvars` changes: `prefix`, `region`, the two profiles, and the workload
VPC/subnet `tag:Name` values. Confirm those names against the deployed landing zone first
(LZA names subnets `subnet-<tier>-<az>`, not `<prefix>-<tier>-<az>`).
