# =========================================
# Terraform Provider Configuration
# =========================================
# This file contains only provider configuration and shared data sources

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# AWS Provider Configuration
provider "aws" {
  region = var.aws_region
  
  # NOTE: default_tags disabled due to AWS provider tags_all inconsistency during apply
  # See: https://github.com/hashicorp/terraform-provider-aws/issues (various)
  # Rely on explicit per-resource tags defined throughout the configuration instead.
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Data source for current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}

