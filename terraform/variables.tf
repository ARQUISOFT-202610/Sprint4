variable "region" {
  description = "AWS region (primary region for infrastructure)"
  type        = string
  default     = "us-east-1"
}

variable "ami_id" {
  description = "AMI ID for EC2 instances (Ubuntu 24.04 LTS amd64). If not provided, will use latest Ubuntu 24.04"
  type        = string
  default     = "" # Empty string = use data source
}

variable "key_name" {
  description = "EC2 Key Pair name (will be auto-generated if not provided)"
  type        = string
  default     = "arquisoft-key"
}

variable "db_password" {
  description = "RDS PostgreSQL master password"
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub PAT for cloning private repositories"
  type        = string
  sensitive   = true
}

variable "recipient_email" {
  description = "Recipient email for SES notifications (must be verified in AWS SES console)"
  type        = string
  default     = "c.ochoao@uniandes.edu.co"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.recipient_email))
    error_message = "Recipient email must be a valid email address."
  }
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "arquisoft"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    CreatedBy   = "Terraform"
    CreatedAt   = timestamp()
  }
}
