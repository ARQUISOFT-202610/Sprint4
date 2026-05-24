variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnets" {
  description = "Public subnets for Celery workers"
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
}

variable "env_file" {
  description = "Environment file content"
  type        = string
  default     = ""
}

variable "iam_instance_profile" {
  description = "IAM instance profile for CloudWatch Agent"
  type        = string
  default     = null
}

# Auto Scaling
variable "desired_capacity" {
  description = "Desired number of Celery workers"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of Celery workers"
  type        = number
  default     = 3
}

variable "min_size" {
  description = "Minimum number of Celery workers"
  type        = number
  default     = 1
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

