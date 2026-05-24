output "alb_id" {
  description = "ID of the ALB"
  value       = aws_lb.main.id
}

output "alb_arn" {
  description = "ARN of the ALB"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the ALB"
  value       = aws_lb.main.zone_id
}

output "alb_sg_id" {
  description = "Security Group ID of the ALB"
  value       = aws_security_group.alb_sg.id
}

output "target_group_id" {
  description = "ID of the target group (Django)"
  value       = aws_lb_target_group.main.id
}

output "target_group_arn" {
  description = "ARN of the target group (Django)"
  value       = aws_lb_target_group.main.arn
}

output "target_group_name" {
  description = "Name of the target group (Django)"
  value       = aws_lb_target_group.main.name
}

output "fastapi_target_group_arn" {
  description = "ARN of the FastAPI target group"
  value       = try(aws_lb_target_group.fastapi[0].arn, null)
}

output "fastapi_target_group_id" {
  description = "ID of the FastAPI target group"
  value       = try(aws_lb_target_group.fastapi[0].id, null)
}

output "fastapi_target_group_name" {
  description = "Name of the FastAPI target group"
  value       = try(aws_lb_target_group.fastapi[0].name, null)
}

output "listener_arn" {
  description = "ARN of the listener"
  value       = aws_lb_listener.main.arn
}
