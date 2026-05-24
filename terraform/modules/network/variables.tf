# Network module variables
# No input variables needed for v1 (hardcoded CIDR blocks)

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
