# ─────────────────────────────────────────────────────────────────────────────
# Look up the LZA-managed VPCs and subnets to attach the connectivity test to.
# Name patterns default to LZA conventions; override per-customer in tfvars if the
# deployed tag:Name values differ (confirm with:
#   aws ec2 describe-vpcs --query "Vpcs[].Tags[?Key=='Name'].Value" ...
#   aws ec2 describe-subnets --query "Subnets[].Tags[?Key=='Name'].Value" ... )
# ─────────────────────────────────────────────────────────────────────────────

locals {
  ingress_vpc_name = replace(var.ingress_vpc_name, "PREFIX", var.prefix) # PREFIX-ingress -> <prefix>-ingress
}

# --- Perimeter account: Ingress VPC (public ALB lives here) ---
data "aws_vpc" "ingress" {
  provider = aws.perimeter
  filter {
    name   = "tag:Name"
    values = [local.ingress_vpc_name]
  }
}

data "aws_subnets" "ingress_public" {
  provider = aws.perimeter
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.ingress.id]
  }
  filter {
    name   = "tag:Name"
    values = [var.ingress_public_subnet_pattern]
  }
}

# --- Workload (staging) account: internal ALB + ECS live here ---
data "aws_vpc" "staging" {
  provider = aws.staging
  filter {
    name   = "tag:Name"
    values = [var.workload_vpc_name]
  }
}

data "aws_subnets" "staging_loadbalancer" {
  provider = aws.staging
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.staging.id]
  }
  filter {
    name   = "tag:Name"
    values = [var.workload_lb_subnet_pattern]
  }
}

data "aws_subnets" "staging_private" {
  provider = aws.staging
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.staging.id]
  }
  filter {
    name   = "tag:Name"
    values = [var.workload_private_subnet_pattern]
  }
}
