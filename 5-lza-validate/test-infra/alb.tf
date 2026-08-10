# ─────────────────────────────────────────────────────────────────────────────
# Two-ALB cross-account ingress chain:
#
#   Internet :80  → Public ALB (Perimeter, the ingress public subnets)
#                 → cross-account IP target group on :443  (crosses TGW + NFW)
#                 → Internal ALB :443 (workload, the workload loadbalancer subnets)
#                 → ECS Fargate nginx :80 (Staging private subnets)
#
# The public ALB can't register targets in another account/VPC directly, so it
# targets the internal ALB's private IPs as IP targets. The cross-firewall leg
# is 443 because that's the only port the NFW east-west policy passes between
# the ingress (<ingress-vpc-cidr>) and staging (<workload-vpc-cidr>) VPCs.
# ─────────────────────────────────────────────────────────────────────────────

# =============================================================================
# STAGING ACCOUNT — internal ALB (HTTPS:443) in the workload loadbalancer subnets
# =============================================================================

resource "aws_security_group" "internal_alb" {
  provider    = aws.staging
  name        = "${var.prefix}-stg-net-test-int-alb"
  description = "Internal ALB - HTTPS:443 from the Ingress VPC via TGW/NFW"
  vpc_id      = data.aws_vpc.staging.id

  ingress {
    description = "HTTPS from Ingress VPC (public ALB targets via TGW, inspected by NFW)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.ingress.cidr_block] # <ingress-vpc-cidr>
  }

  egress {
    description = "To ECS tasks in this VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.staging.cidr_block] # <workload-vpc-cidr>
  }

  tags = merge(var.tags, { Name = "${var.prefix}-stg-net-test-int-alb" })
}

resource "aws_lb" "internal" {
  provider           = aws.staging
  name               = "${var.prefix}-stg-net-int"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.internal_alb.id]
  subnets            = data.aws_subnets.staging_loadbalancer.ids

  drop_invalid_header_fields = true
  tags                       = merge(var.tags, { Name = "${var.prefix}-stg-net-int" })
}

# ECS task IP target group (HTTP:80 — intra-VPC, not inspected by NFW).
resource "aws_lb_target_group" "ecs" {
  provider    = aws.staging
  name        = "${var.prefix}-stg-net-ecs"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.staging.id
  target_type = "ip" # Fargate task ENIs register by IP

  health_check {
    path                = "/"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }

  deregistration_delay = 15
  tags                 = merge(var.tags, { Name = "${var.prefix}-stg-net-ecs" })
}

resource "aws_lb_listener" "internal_https" {
  provider          = aws.staging
  load_balancer_arn = aws_lb.internal.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.internal.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs.arn
  }

  tags = var.tags
}

# =============================================================================
# PERIMETER ACCOUNT — public ALB (HTTP:80 from internet) in ingress-public subnets
# =============================================================================

resource "aws_security_group" "public_alb" {
  provider    = aws.perimeter
  name        = "${var.prefix}-stg-net-test-pub-alb"
  description = "Public ALB - HTTP:80 from internet, HTTPS:443 egress to staging via TGW"
  vpc_id      = data.aws_vpc.ingress.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTPS to internal ALB in staging VPC (via TGW/NFW)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.staging.cidr_block] # <workload-vpc-cidr>
  }

  tags = merge(var.tags, { Name = "${var.prefix}-stg-net-test-pub-alb" })
}

resource "aws_lb" "public" {
  provider           = aws.perimeter
  name               = "${var.prefix}-stg-net-pub"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.public_alb.id]
  subnets            = data.aws_subnets.ingress_public.ids

  drop_invalid_header_fields = true
  tags                       = merge(var.tags, { Name = "${var.prefix}-stg-net-pub" })
}

# Cross-account IP target group: targets the internal ALB's private IPs on 443.
resource "aws_lb_target_group" "cross_account" {
  provider    = aws.perimeter
  name        = "${var.prefix}-stg-net-xacct"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = data.aws_vpc.ingress.id
  target_type = "ip"

  health_check {
    protocol            = "HTTPS"
    path                = "/"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
  }

  tags = merge(var.tags, { Name = "${var.prefix}-stg-net-xacct" })
}

resource "aws_lb_listener" "public_http" {
  provider          = aws.perimeter
  load_balancer_arn = aws_lb.public.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cross_account.arn
  }

  tags = var.tags
}

# Register the internal ALB's per-AZ private IPs as cross-account targets.
# AWS doesn't expose ALB private IPs on the aws_lb resource, and they're in a
# different account/VPC, so resolve them by DNS and register via the CLI.
# Re-runs whenever the internal ALB DNS changes (i.e. on recreate).
resource "null_resource" "register_internal_alb_ips" {
  triggers = {
    internal_alb_dns = aws_lb.internal.dns_name
    tg_arn           = aws_lb_target_group.cross_account.arn
    profile          = var.perimeter_profile
    region           = var.region
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      DNS="${aws_lb.internal.dns_name}"
      echo "Resolving internal ALB ${aws_lb.internal.dns_name} ..."
      # Give DNS a moment to publish after the ALB is created.
      IPS=""
      for i in 1 2 3 4 5 6; do
        IPS=$(dig +short "$DNS" | grep -E '^[0-9]+\.' || true)
        [ -n "$IPS" ] && break
        echo "  no IPs yet (attempt $i), waiting 10s..."; sleep 10
      done
      if [ -z "$IPS" ]; then
        echo "WARNING: could not resolve $DNS. Register manually:"
        echo "  aws elbv2 register-targets --target-group-arn ${aws_lb_target_group.cross_account.arn} \\"
        echo "    --targets Id=<ip>,Port=443,AvailabilityZone=all --profile ${var.perimeter_profile} --region ${var.region}"
        exit 0
      fi
      for IP in $IPS; do
        echo "Registering $IP:443 (AZ=all) ..."
        aws elbv2 register-targets \
          --target-group-arn "${aws_lb_target_group.cross_account.arn}" \
          --targets Id=$IP,Port=443,AvailabilityZone=all \
          --profile ${var.perimeter_profile} --region ${var.region}
      done
    EOT
  }

  depends_on = [aws_lb_listener.internal_https]
}
