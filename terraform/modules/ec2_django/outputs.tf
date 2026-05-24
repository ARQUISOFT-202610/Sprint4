output "asg_name" {
  description = "Django Auto Scaling Group name"
  value       = aws_autoscaling_group.django_asg.name
}

output "django_sg_id" {
  description = "Django EC2 security group ID (for RDS allowlist)"
  value       = aws_security_group.django_sg.id
}
