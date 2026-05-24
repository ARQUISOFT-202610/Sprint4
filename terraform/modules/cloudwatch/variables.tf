# ============================================================================
# CloudWatch Log Groups - Input Variables
# ============================================================================

variable "log_group_prefix" {
  description = "Prefix for log group names (e.g., /arquisoft)"
  type        = string
  default     = "/arquisoft"
}

variable "retention_days" {
  description = "Number of days to retain logs (ASR2: 90 days minimum for audit compliance)"
  type        = number
  default     = 90

  validation {
    condition     = var.retention_days >= 90
    error_message = "Retention days must be at least 90 for ASR2 compliance (audit logs)."
  }
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
