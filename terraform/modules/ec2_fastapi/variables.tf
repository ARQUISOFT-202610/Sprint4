variable "vpc_id" {
  description = "VPC ID"
}

variable "public_subnets" {
  description = "Public subnets"
  type        = list(string)
}

variable "ami_id" {
  description = "AMI ID"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.micro"
}

variable "key_name" {
  description = "SSH Key"
}

variable "github_token" {
  description = "GitHub token"
  sensitive   = true
}

variable "env_file" {
  description = "Contenido del archivo .env"
}

variable "iam_instance_profile" {
  description = "IAM instance profile for CloudWatch Agent"
  type        = string
  default     = null
}

# Auto Scaling
variable "desired_capacity" {
  default = 1
}

variable "max_size" {
  default = 3
}

variable "min_size" {
  default = 1
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

variable "target_group_arn" {
  description = "ARN of ALB target group for FastAPI (from alb module)"
  type        = string
}

variable "alb_sg_id" {
  description = "Security Group ID of the ALB (from alb module)"
  type        = string
}
