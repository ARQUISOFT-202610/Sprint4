output "asg_name" {
  description = "Celery Auto Scaling Group name"
  value       = aws_autoscaling_group.celery_asg.name
}

output "security_group_id" {
  description = "Celery workers security group ID"
  value       = aws_security_group.celery_sg.id
}

output "celery_sg_id" {
  description = "Celery workers security group ID (alias for security_group_id)"
  value       = aws_security_group.celery_sg.id
}

output "launch_template_id" {
  description = "Celery launch template ID"
  value       = aws_launch_template.celery_lt.id
}
