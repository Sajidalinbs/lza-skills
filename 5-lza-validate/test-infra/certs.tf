# ─────────────────────────────────────────────────────────────────────────────
# Self-signed TLS cert for the internal ALB's HTTPS:443 listener.
#
# Why HTTPS/443 and not plain HTTP/80?
#   The central NFW east-west policy is STRICT_ORDER with a default drop. The
#   ONLY pass rules between the Ingress VPC (<ingress-vpc-cidr>) and the Staging VPC
#   (<workload-vpc-cidr>) are on port 443 (sids 4200/4201) — there is no port-80 rule.
#   So the cross-firewall leg (public ALB -> internal ALB) must run on 443, or
#   the firewall silently drops it. This mirrors the real production data path.
#
# An ALB does NOT validate the backend/target certificate, so a self-signed
# cert imported into ACM is sufficient — no DNS/domain validation needed.
# ─────────────────────────────────────────────────────────────────────────────

resource "tls_private_key" "internal" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "internal" {
  private_key_pem = tls_private_key.internal.private_key_pem

  subject {
    common_name  = "${var.prefix}-stg-net-test.internal"
    organization = "lza-test-connectivity"
  }

  validity_period_hours = 720 # 30 days — this is throwaway test infra
  early_renewal_hours   = 0

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]

  dns_names = ["${var.prefix}-stg-net-test.internal"]
}

resource "aws_acm_certificate" "internal" {
  provider         = aws.staging
  private_key      = tls_private_key.internal.private_key_pem
  certificate_body = tls_self_signed_cert.internal.cert_pem

  tags = merge(var.tags, { Name = "${var.prefix}-stg-net-test-internal" })
}
