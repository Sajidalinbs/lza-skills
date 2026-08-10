variable "region" {
  description = "AWS region (must match the LZA HomeRegion)."
  type        = string
}

variable "prefix" {
  description = "Resource naming prefix (matches LZA AcceleratorPrefix, e.g. acme)."
  type        = string
}

variable "perimeter_profile" {
  description = "AWS CLI profile (or assume-role profile) for the Perimeter account."
  type        = string
}

variable "staging_profile" {
  description = "AWS CLI profile (or assume-role profile) for the workload (staging) account under test."
  type        = string
}

# ---- Resource-name lookups (LZA conventions; override if your tags differ) ----
variable "ingress_vpc_name" {
  description = "tag:Name of the Perimeter ingress VPC."
  type        = string
  default     = "PREFIX-ingress" # PREFIX is replaced with var.prefix in data.tf
}
variable "ingress_public_subnet_pattern" {
  description = "tag:Name glob for the ingress public subnets."
  type        = string
  default     = "subnet-ingress-public-*"
}
variable "workload_vpc_name" {
  description = "tag:Name of the workload VPC under test (e.g. acme-staging)."
  type        = string
}
variable "workload_lb_subnet_pattern" {
  description = "tag:Name glob for the workload loadbalancer subnets (internal ALB)."
  type        = string
}
variable "workload_private_subnet_pattern" {
  description = "tag:Name glob for the workload private subnets (ECS task ENIs)."
  type        = string
}

# Docker Hub images — must be pullable through the NFW egress allowlist
# (*.docker.io / *.docker.com are allowed; public.ecr.aws is NOT).
variable "web_image" {
  type    = string
  default = "nginx:alpine"
}
variable "egress_probe_image" {
  type    = string
  default = "curlimages/curl:latest"
}

variable "tags" {
  type = map(string)
  default = {
    Purpose   = "network-flow-test"
    Component = "test-connectivity"
    ManagedBy = "terraform"
  }
}
