output "db_endpoint" {
  description = "RDS endpoint with port"
  value       = aws_db_instance.postgres.endpoint
}

output "db_address" {
  description = "RDS endpoint hostname (without port)"
  value       = aws_db_instance.postgres.address
}

output "db_port" {
  description = "RDS port"
  value       = aws_db_instance.postgres.port
}

output "db_name" {
  description = "RDS database name"
  value       = aws_db_instance.postgres.db_name
}

output "db_username" {
  description = "RDS master username"
  value       = aws_db_instance.postgres.username
}

output "db_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.postgres.id
}

output "rds_sg_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds_sg.id
}
