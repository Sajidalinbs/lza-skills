output "public_alb_dns_name" {
  description = "Public ALB DNS name — curl this (HTTP) to test the ingress flow."
  value       = aws_lb.public.dns_name
}

output "internal_alb_dns_name" {
  description = "Internal ALB DNS name in the staging VPC (HTTPS:443)."
  value       = aws_lb.internal.dns_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name in the staging account."
  value       = aws_ecs_cluster.test.name
}

output "ecs_log_group" {
  description = "CloudWatch log group — egress-probe results land here."
  value       = aws_cloudwatch_log_group.ecs.name
}

output "test_commands" {
  description = "Run these to verify both flows."
  value       = <<-EOT

  ─── 1. INGRESS  (Internet -> Perimeter ALB -> TGW -> NFW -> Staging ALB -> ECS) ──
  curl -s http://${aws_lb.public.dns_name}/ | head

    Expected: nginx welcome HTML.
    First 200 typically lands ~3 min after apply (ECS pull + 2x health checks).
    A 503 for the first ~60s is normal while the cross-account target goes healthy.

  ─── 2. EGRESS  (ECS -> TGW -> NFW -> NAT -> Internet) ───────────────────────────
  aws logs tail ${aws_cloudwatch_log_group.ecs.name} \
    --log-stream-name-prefix egress --since 5m --follow \
    --profile ${var.staging_profile} --region ${var.region}

    Expected every 30s:
      amazonaws (ALLOW):  HTTP 400 in 0.3s     # TLS handshake OK = NFW let *.amazonaws.com through
      example.com (DENY): blocked (expected)   # NFW strict-order default-deny dropped it

  ─── Health by layer ─────────────────────────────────────────────────────────────
  # Cross-account TG (Perimeter) — expect the internal ALB IPs healthy
  aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.cross_account.arn} \
    --profile ${var.perimeter_profile} --region ${var.region}

  # ECS TG (Staging) — expect 1 healthy task IP
  aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.ecs.arn} \
    --profile ${var.staging_profile} --region ${var.region}

  ─── Cleanup ─────────────────────────────────────────────────────────────────────
  terraform destroy
  EOT
}
