# ============================================================================
# Root-level Outputs - Infrastructure Information
# ============================================================================

# ─────────────────────────────────────────
# EC2 Key Pair Outputs
# ─────────────────────────────────────────
output "ec2_key_pair_name" {
  description = "EC2 Key Pair name for SSH access"
  value       = module.ec2_keypair.key_name
}

output "ec2_private_key_path" {
  description = "Local path to the private key file"
  value       = module.ec2_keypair.private_key_path
  sensitive   = true
}

# ─────────────────────────────────────────
# Network Outputs
# ─────────────────────────────────────────
output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.network.vpc_cidr
}

output "public_subnets" {
  description = "Public subnet IDs (for ALB and EC2)"
  value       = module.network.public_subnets
}

output "private_subnets" {
  description = "Private subnet IDs (for RDS, Celery, etc)"
  value       = module.network.private_subnets
}

output "public_subnet_azs" {
  description = "Availability zones for public subnets"
  value       = module.network.public_subnet_azs
}

output "private_subnet_azs" {
  description = "Availability zones for private subnets"
  value       = module.network.private_subnet_azs
}

# ─────────────────────────────────────────
# Django (EC2 + ALB) Outputs
# ─────────────────────────────────────────
output "django_alb_dns_name" {
  description = "Django ALB DNS name (access your app via this URL)"
  value       = module.alb.alb_dns_name
}

output "django_alb_zone_id" {
  description = "Zone ID of Django ALB"
  value       = module.alb.alb_zone_id
}

output "django_alb_arn" {
  description = "ARN of Django ALB"
  value       = module.alb.alb_arn
}

output "django_target_group_arn" {
  description = "Django ALB Target Group ARN"
  value       = module.alb.target_group_arn
}

output "django_alb_sg_id" {
  description = "ALB Security Group ID"
  value       = module.alb.alb_sg_id
}

output "django_asg_name" {
  description = "Django Auto Scaling Group name"
  value       = module.ec2_django.asg_name
}

output "django_sg_id" {
  description = "Django EC2 Security Group ID"
  value       = module.ec2_django.django_sg_id
}

# ─────────────────────────────────────────
# RDS (PostgreSQL) Outputs
# ─────────────────────────────────────────
output "rds_endpoint" {
  description = "RDS database endpoint (with port)"
  value       = module.rds.db_endpoint
}

output "rds_host" {
  description = "RDS database hostname (without port)"
  value       = module.rds.db_address
}

output "rds_port" {
  description = "RDS database port"
  value       = module.rds.db_port
}

output "rds_database_name" {
  description = "RDS database name"
  value       = module.rds.db_name
}

output "rds_master_username" {
  description = "RDS master username"
  value       = module.rds.db_username
  sensitive   = true
}

output "rds_security_group_id" {
  description = "RDS Security Group ID"
  value       = module.rds.rds_sg_id
}

# ─────────────────────────────────────────
# Celery Workers (EC2 + ASG) Outputs
# ─────────────────────────────────────────
output "celery_asg_name" {
  description = "Celery Auto Scaling Group name"
  value       = module.ec2_celery.asg_name
}

output "celery_security_group_id" {
  description = "Celery EC2 Security Group ID"
  value       = module.ec2_celery.security_group_id
}

# ─────────────────────────────────────────
# Frontend (Nginx + React) Outputs
# ─────────────────────────────────────────
output "frontend_asg_name" {
  description = "Frontend Auto Scaling Group name"
  value       = module.ec2_frontend.asg_name
}

output "frontend_security_group_id" {
  description = "Frontend EC2 Security Group ID"
  value       = module.ec2_frontend.security_group_id
}

# ─────────────────────────────────────────
# SQS Queue Outputs
# ─────────────────────────────────────────
output "sqs_queue_url" {
  description = "SQS Queue URL for Celery tasks"
  value       = module.sqs.queue_url
}

output "sqs_queue_arn" {
  description = "SQS Queue ARN"
  value       = module.sqs.queue_arn
}

output "sqs_queue_name" {
  description = "SQS Queue name"
  value       = module.sqs.queue_name
}

# ─────────────────────────────────────────
# CloudWatch Logs (ASR2 - Audit Logs)
# ─────────────────────────────────────────
output "cloudwatch_log_groups" {
  description = "CloudWatch log groups for Django, Celery, and security events"
  value = {
    django              = module.cloudwatch.django_log_group_name
    django_security     = module.cloudwatch.django_security_log_group_name
    celery              = module.cloudwatch.celery_log_group_name
    celery_failures     = module.cloudwatch.celery_failures_log_group_name
    retention_days      = 90
  }
}

output "cloudwatch_log_groups_arns" {
  description = "CloudWatch log group ARNs"
  value = {
    django              = module.cloudwatch.django_log_group_arn
    django_security     = module.cloudwatch.django_security_log_group_arn
    celery              = module.cloudwatch.celery_log_group_arn
    celery_failures     = module.cloudwatch.celery_failures_log_group_arn
  }
}

# ─────────────────────────────────────────
# AWS SES Configuration
# ─────────────────────────────────────────
output "ses_email_identities" {
  description = "SES email identities (sender and recipient)"
  value = {
    sender             = module.ses.sender_email
    recipient          = module.ses.recipient_email
    verification_note  = "Both emails must be manually verified in AWS SES console before emails can be sent"
  }
}

output "ses_templates" {
  description = "SES email templates for analysis results"
  value = {
    success_template = module.ses.success_template_name
    failure_template = module.ses.failure_template_name
  }
}

output "ses_configuration_summary" {
  description = "SES configuration summary"
  value       = module.ses.ses_configuration_summary
}

# ─────────────────────────────────────────
# Infrastructure Summary
# ─────────────────────────────────────────
output "infrastructure_summary" {
  description = "Summary of deployed infrastructure"
  value = {
    project          = var.project_name
    environment      = var.environment
    region           = var.region
    vpc_id           = module.network.vpc_id
    app_url          = "http://${module.alb.alb_dns_name}"
    db_endpoint      = module.rds.db_endpoint
    sqs_queue_url    = module.sqs.queue_url
    celery_workers   = module.ec2_celery.asg_name
    frontend_servers = module.ec2_frontend.asg_name
    cloudwatch_logs  = "4 log groups created (/arquisoft/django, /arquisoft/django/security, /arquisoft/celery, /arquisoft/celery/failures)"
    ses_configured   = "2 email templates configured (analisis-resultado-exito, analisis-resultado-error)"
  }
}
