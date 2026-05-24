output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnets" {
  description = "List of public subnet IDs (for ALB and EC2)"
  value       = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

output "private_subnets" {
  description = "List of private subnet IDs (for RDS, Celery, etc)"
  value       = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

output "public_subnet_azs" {
  description = "List of AZs for public subnets"
  value       = [aws_subnet.public_1.availability_zone, aws_subnet.public_2.availability_zone]
}

output "private_subnet_azs" {
  description = "List of AZs for private subnets"
  value       = [aws_subnet.private_1.availability_zone, aws_subnet.private_2.availability_zone]
}

output "igw_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.igw.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}
