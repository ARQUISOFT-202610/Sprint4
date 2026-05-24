variable "key_name" {
  description = "Name of the EC2 Key Pair"
  type        = string
  default     = "arquisoft-key"
}

variable "local_key_path" {
  description = "Local path to save the private key"
  type        = string
  default     = "~/.ssh"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
