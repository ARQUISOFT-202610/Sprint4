output "instance_id" {
  description = "DynamoDB Local EC2 instance ID"
  value       = aws_instance.dynamodb.id
}

output "private_ip" {
  description = "DynamoDB Local EC2 private IP address"
  value       = aws_instance.dynamodb.private_ip
}

output "public_ip" {
  description = "DynamoDB Local EC2 public IP address"
  value       = aws_instance.dynamodb.public_ip
}

output "dynamodb_sg_id" {
  description = "DynamoDB Local security group ID"
  value       = aws_security_group.dynamodb_sg.id
}
