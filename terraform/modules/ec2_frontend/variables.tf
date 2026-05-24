variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnets" {
  description = "Public subnets for Frontend"
  type        = list(string)
}

variable "ami_id" {
  description = "AMI ID"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "SSH Key Pair name"
  type        = string
}

variable "github_token" {
  description = "GitHub token for cloning repo"
  type        = string
  sensitive   = true
  default     = ""
}

variable "django_alb_dns" {
  description = "DNS name of Django ALB for API proxy in Nginx"
  type        = string
}

variable "tls_certificate_pem" {
  description = "TLS certificate in PEM format for HTTPS"
  type        = string
  sensitive   = true
}

variable "tls_private_key_pem" {
  description = "TLS private key in PEM format for HTTPS"
  type        = string
  sensitive   = true
}

# Auto Scaling
variable "desired_capacity" {
  description = "Desired number of Frontend instances"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of Frontend instances"
  type        = number
  default     = 4
}

variable "min_size" {
  description = "Minimum number of Frontend instances"
  type        = number
  default     = 1
}

variable "iam_instance_profile" {
  description = "IAM instance profile name to attach to frontend instances"
  type        = string
  default     = "LabInstanceProfile"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
