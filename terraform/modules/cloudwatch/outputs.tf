# ============================================================================
# CloudWatch Log Groups - Outputs
# ============================================================================

output "django_log_group_name" {
  description = "Django application log group name"
  value       = aws_cloudwatch_log_group.django.name
}

output "django_log_group_arn" {
  description = "Django application log group ARN"
  value       = aws_cloudwatch_log_group.django.arn
}

output "django_security_log_group_name" {
  description = "Django security/audit log group name (ASR2)"
  value       = aws_cloudwatch_log_group.django_security.name
}

output "django_security_log_group_arn" {
  description = "Django security/audit log group ARN (ASR2)"
  value       = aws_cloudwatch_log_group.django_security.arn
}

output "celery_log_group_name" {
  description = "Celery worker log group name"
  value       = aws_cloudwatch_log_group.celery.name
}

output "celery_log_group_arn" {
  description = "Celery worker log group ARN"
  value       = aws_cloudwatch_log_group.celery.arn
}

output "celery_failures_log_group_name" {
  description = "Celery failures/errors log group name"
  value       = aws_cloudwatch_log_group.celery_failures.name
}

output "celery_failures_log_group_arn" {
  description = "Celery failures/errors log group ARN"
  value       = aws_cloudwatch_log_group.celery_failures.arn
}

output "log_groups_summary" {
  description = "Summary of all log groups"
  value = {
    django_app       = aws_cloudwatch_log_group.django.name
    django_security  = aws_cloudwatch_log_group.django_security.name
    celery_app       = aws_cloudwatch_log_group.celery.name
    celery_failures  = aws_cloudwatch_log_group.celery_failures.name
    retention_days   = var.retention_days
  }
}
