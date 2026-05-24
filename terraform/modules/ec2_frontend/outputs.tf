output "asg_name" {
  description = "Frontend Auto Scaling Group name"
  value       = aws_autoscaling_group.frontend_asg.name
}

output "security_group_id" {
  description = "Frontend security group ID"
  value       = aws_security_group.frontend_sg.id
}

output "launch_template_id" {
  description = "Frontend launch template ID"
  value       = aws_launch_template.frontend_lt.id
}
