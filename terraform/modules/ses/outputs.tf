# ============================================================================
# AWS SES - Outputs
# ============================================================================

output "sender_email" {
  description = "Verified sender email address (if email verification enabled)"
  value       = try(aws_ses_email_identity.sender[0].email, "Not created - enable_email_verification is false")
}

output "sender_email_arn" {
  description = "ARN of sender email identity (if email verification enabled)"
  value       = try(aws_ses_email_identity.sender[0].arn, "Not created - enable_email_verification is false")
}

output "recipient_email" {
  description = "Verified recipient email address (if email verification enabled)"
  value       = try(aws_ses_email_identity.recipient[0].email, "Not created - enable_email_verification is false")
}

output "recipient_email_arn" {
  description = "ARN of recipient email identity (if email verification enabled)"
  value       = try(aws_ses_email_identity.recipient[0].arn, "Not created - enable_email_verification is false")
}

output "success_template_name" {
  description = "Name of success email template (if templates enabled)"
  value       = try(aws_ses_template.success[0].name, "Not created - enable_templates is false")
}

output "failure_template_name" {
  description = "Name of failure email template (if templates enabled)"
  value       = try(aws_ses_template.failure[0].name, "Not created - enable_templates is false")
}

output "ses_configuration_summary" {
  description = "Summary of SES configuration and setup status"
  value = {
    email_verification_enabled = var.enable_email_verification
    templates_enabled          = var.enable_templates
    sender_email               = try(aws_ses_email_identity.sender[0].email, var.sender_email)
    recipient_email            = try(aws_ses_email_identity.recipient[0].email, var.recipient_email)
    success_template           = try(aws_ses_template.success[0].name, var.success_template_name)
    failure_template           = try(aws_ses_template.failure[0].name, var.failure_template_name)
    verification_status        = var.enable_email_verification ? "MANUAL verification required in AWS Console" : "SKIPPED - Academy IAM restrictions"
    templates_status           = var.enable_templates ? "Created automatically" : "SKIPPED - Academy IAM restrictions, create manually in AWS Console"
  }
}
