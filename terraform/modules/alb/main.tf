# ─────────────────────────────────────────
# Security Group - ALB
# ─────────────────────────────────────────
resource "aws_security_group" "alb_sg" {
  name        = "arquisoft-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from internet"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS from internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(
    var.tags,
    {
      Name = "arquisoft-alb-sg"
    }
  )
}

# ─────────────────────────────────────────
# Application Load Balancer
# ─────────────────────────────────────────
resource "aws_lb" "main" {
  name               = var.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.subnets

  enable_deletion_protection = false

  tags = merge(
    var.tags,
    {
      Name = var.alb_name
    }
  )
}

# ─────────────────────────────────────────
# Target Group
# ─────────────────────────────────────────
resource "aws_lb_target_group" "main" {
  name        = "${var.alb_name}-tg"
  port        = var.target_port
  protocol    = var.target_protocol
  vpc_id      = var.vpc_id
  
  health_check {
    path                = var.health_check_path
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    healthy_threshold   = var.healthy_threshold
    unhealthy_threshold = var.unhealthy_threshold
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.alb_name}-tg"
    }
  )
}

# ─────────────────────────────────────────
# Target Group for FastAPI (Optional)
# ─────────────────────────────────────────
resource "aws_lb_target_group" "fastapi" {
  count       = var.enable_fastapi_target ? 1 : 0
  name        = "${var.alb_name}-fastapi-tg"
  port        = var.fastapi_target_port
  protocol    = var.target_protocol
  vpc_id      = var.vpc_id
  
  health_check {
    path                = var.fastapi_health_check_path
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    healthy_threshold   = var.healthy_threshold
    unhealthy_threshold = var.unhealthy_threshold
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.alb_name}-fastapi-tg"
    }
  )
}

# ─────────────────────────────────────────
# ALB Listener
# ─────────────────────────────────────────
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = var.alb_port
  protocol          = var.alb_protocol

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# ─────────────────────────────────────────
# ALB Listener Rule - FastAPI Path-Based Routing
# ─────────────────────────────────────────
resource "aws_lb_listener_rule" "fastapi_path_routing" {
  count            = var.enable_fastapi_target ? 1 : 0
  listener_arn     = aws_lb_listener.main.arn
  priority         = 1
  
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.fastapi[0].arn
  }
  
  condition {
    path_pattern {
      values = ["/fastapi/*"]
    }
  }
}
