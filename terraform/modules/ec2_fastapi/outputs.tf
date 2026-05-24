output "asg_name" {
  description = "FastAPI Auto Scaling Group name"
  value       = aws_autoscaling_group.fastapi_asg.name
}

output "fastapi_sg_id" {
  description = "FastAPI EC2 security group ID"
  value       = aws_security_group.fastapi_sg.id
}
