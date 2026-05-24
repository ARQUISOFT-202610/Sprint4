variable "queue_name" {
  description = "Name of the SQS queue for Celery tasks"
  type        = string
  default     = "arquisoft-celery-queue"
}

variable "visibility_timeout_seconds" {
  description = "Visibility timeout for SQS messages in seconds"
  type        = number
  default     = 300
}

variable "message_retention_seconds" {
  description = "Message retention period in seconds (up to 14 days = 1209600)"
  type        = number
  default     = 1209600
}

variable "delay_seconds" {
  description = "Default delay for messages in seconds"
  type        = number
  default     = 0
}

variable "receive_wait_time_seconds" {
  description = "Long polling timeout in seconds"
  type        = number
  default     = 20
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
