variable "vpc_id" {
  description = "VPC ID where ALB will be deployed"
  type        = string
}

variable "subnets" {
  description = "Public subnet IDs for ALB (Multi-AZ recommended)"
  type        = list(string)
}

variable "alb_name" {
  description = "Name of the Application Load Balancer"
  type        = string
  default     = "arquisoft-alb"
}

variable "alb_port" {
  description = "Port for ALB listener"
  type        = number
  default     = 80
}

variable "alb_protocol" {
  description = "Protocol for ALB listener"
  type        = string
  default     = "HTTP"
}

variable "target_port" {
  description = "Port for target instances"
  type        = number
  default     = 8000
}

variable "target_protocol" {
  description = "Protocol for targets"
  type        = string
  default     = "HTTP"
}

variable "health_check_path" {
  description = "Health check path"
  type        = string
  default     = "/"
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
}

variable "healthy_threshold" {
  description = "Number of successful checks before healthy"
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Number of failed checks before unhealthy"
  type        = number
  default     = 2
}

# FastAPI Target Group variables
variable "enable_fastapi_target" {
  description = "Enable FastAPI target group"
  type        = bool
  default     = false
}

variable "fastapi_target_port" {
  description = "Port for FastAPI target instances"
  type        = number
  default     = 8001
}

variable "fastapi_health_check_path" {
  description = "FastAPI health check path"
  type        = string
  default     = "/health"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
