terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# Public ALB lives in the Perimeter account (the ingress VPC).
provider "aws" {
  alias   = "perimeter"
  region  = var.region
  profile = var.perimeter_profile
}

# Internal ALB + ECS tasks live in the workload account (the workload VPC).
provider "aws" {
  alias   = "staging"
  region  = var.region
  profile = var.staging_profile
}
