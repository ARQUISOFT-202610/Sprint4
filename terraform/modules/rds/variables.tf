variable "vpc_id" {
  description = "VPC ID"
}

variable "private_subnets" {
  description = "Private subnets for RDS"
  type        = list(string)
}

variable "allowed_sg_ids" {
  description = "Security groups allowed to access RDS"
  type        = list(string)
}

# DB config
variable "db_name" {
  default = "django_db"
}

variable "db_username" {
  default = "postgres"
}

variable "db_password" {
  description = "Database password"
  sensitive   = true
}

variable "db_instance_class" {
  default = "db.t3.micro"
}

variable "multi_az" {
  description = "Enable Multi-AZ for high availability"
  default     = true # Habilitado por defecto para HA
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}