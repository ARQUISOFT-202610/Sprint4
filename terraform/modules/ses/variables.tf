# ============================================================================
# AWS SES - Input Variables
# ============================================================================

variable "sender_email" {
  description = "Sender email address (must be verified in AWS SES)"
  type        = string
  default     = "cristianochoa858@gmail.com"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sender_email))
    error_message = "Sender email must be a valid email address."
  }
}

variable "recipient_email" {
  description = "Recipient email address for analysis notifications (must be verified in AWS SES)"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.recipient_email))
    error_message = "Recipient email must be a valid email address."
  }
}

variable "success_template_name" {
  description = "Name of email template for successful analysis"
  type        = string
  default     = "analisis-resultado-exito"
}

variable "failure_template_name" {
  description = "Name of email template for failed analysis"
  type        = string
  default     = "analisis-resultado-error"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

variable "enable_email_verification" {
  description = "Enable automatic email verification (set to false for AWS Academy with restricted SES permissions)"
  type        = bool
  default     = false
}

variable "enable_templates" {
  description = "Enable automatic SES template creation (set to false for AWS Academy with restricted SES permissions)"
  type        = bool
  default     = false
}
