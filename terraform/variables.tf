# =========================================
# Terraform Variables Definition
# =========================================
# This file defines all variables used in the Terraform configuration
# Variable values should be set in terraform.tfvars or passed via -var flag

# AWS Region Configuration
variable "aws_region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in valid format (e.g., us-east-1, eu-west-1)."
  }
}

# Project Identification
variable "project_name" {
  description = "Name of the project used for resource naming convention"
  type        = string
  default     = "secure-docker-project"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

# Environment Configuration
variable "environment" {
  description = "Deployment environment (development, staging, production)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# VPC Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for the Virtual Private Cloud"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

# Public Subnet Configuration (for NAT Gateway)
variable "public_subnet_cidr" {
  description = "CIDR block for public subnet (hosts NAT Gateway)"
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "Public subnet CIDR must be a valid IPv4 CIDR block."
  }
}

# Private Subnet Configuration (for EC2 instances)
variable "private_subnet_cidr" {
  description = "CIDR block for private subnet (hosts EC2 instances)"
  type        = string
  default     = "10.0.2.0/24"

  validation {
    condition     = can(cidrhost(var.private_subnet_cidr, 0))
    error_message = "Private subnet CIDR must be a valid IPv4 CIDR block."
  }
}

# EC2 Instance Type
variable "instance_type" {
  description = "EC2 instance type for Docker host"
  type        = string
  default     = "t3.medium"

  validation {
    # Allow common free-tier and cost-effective types by default
    condition = contains([
      "t2.micro", "t2.small",
      "t3.micro", "t3.small", "t3.medium", "t3.large", "t3.xlarge",
      "t3a.micro", "t3a.small", "t3a.medium", "t3a.large",
      "m5.large", "m5.xlarge", "m5.2xlarge"
    ], var.instance_type)
    error_message = "Instance type must be one of the allowed instance families (t2, t3/t3a, or m5)."
  }
}

# Root Volume Configuration
variable "root_volume_size" {
  description = "Size of the root EBS volume in gigabytes"
  type        = number
  default     = 20

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 100
    error_message = "Root volume size must be between 8 and 100 GB."
  }
}

# CloudWatch Monitoring Configuration
variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for EC2 instances"
  type        = bool
  default     = true
}

# Backup Retention Configuration
variable "backup_retention_days" {
  description = "Number of days to retain automated backups and snapshots"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Backup retention must be between 1 and 35 days."
  }
}