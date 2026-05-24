# ============================================================================
# CloudWatch Logs Module - Log Groups for ArquiSoft Application
# ============================================================================
# Purpose: Create and manage CloudWatch Log Groups for Django, Celery, and
# security audit logs with 90-day retention for ASR2 compliance (audit logs)
# ============================================================================

# Log Group 1: Django Application Logs
resource "aws_cloudwatch_log_group" "django" {
  name              = "${var.log_group_prefix}/django"
  retention_in_days = var.retention_days

  tags = merge(
    var.tags,
    {
      Name = "arquisoft-django-logs"
    }
  )
}

# Log Group 2: Django Security/Audit Logs
# Contains: Authentication, Authorization, Access Control events
resource "aws_cloudwatch_log_group" "django_security" {
  name              = "${var.log_group_prefix}/django/security"
  retention_in_days = var.retention_days

  tags = merge(
    var.tags,
    {
      Name = "arquisoft-django-security-logs"
    }
  )
}

# Log Group 3: Celery Worker Logs
resource "aws_cloudwatch_log_group" "celery" {
  name              = "${var.log_group_prefix}/celery"
  retention_in_days = var.retention_days

  tags = merge(
    var.tags,
    {
      Name = "arquisoft-celery-logs"
    }
  )
}

# Log Group 4: Celery Failures and Errors
# Contains: Task failures, retries, error details
resource "aws_cloudwatch_log_group" "celery_failures" {
  name              = "${var.log_group_prefix}/celery/failures"
  retention_in_days = var.retention_days

  tags = merge(
    var.tags,
    {
      Name = "arquisoft-celery-failures"
    }
  )
}
