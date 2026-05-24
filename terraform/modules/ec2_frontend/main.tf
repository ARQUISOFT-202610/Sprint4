# ─────────────────────────────────────────
# Security Group - Frontend
# ─────────────────────────────────────────
resource "aws_security_group" "frontend_sg" {
  name        = "arquisoft-frontend-sg"
  description = "Allow HTTP/HTTPS and SSH for Frontend"
  vpc_id      = var.vpc_id

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from internet"
  }

  # HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from internet"
  }

  # SSH Access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access from anywhere"
  }

  # Optional: Development port 3000 (React dev server)
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "React dev server (optional)"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "arquisoft-frontend-sg"
    }
  )
}

# ─────────────────────────────────────────
# Launch Template - Frontend
# ─────────────────────────────────────────
resource "aws_launch_template" "frontend_lt" {
  name_prefix   = "frontend-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  key_name = var.key_name

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.frontend_sg.id]
  }

  iam_instance_profile {
    name = var.iam_instance_profile
  }

  user_data = base64encode(templatefile("${path.module}/../../scripts/frontend_deploy.sh", {
    github_token        = var.github_token
    django_alb_dns      = var.django_alb_dns
    tls_certificate_pem = var.tls_certificate_pem
    tls_private_key_pem = var.tls_private_key_pem
  }))

  tag_specifications {
    resource_type = "instance"

    tags = merge(
      var.tags,
      {
        Name = "arquisoft-frontend"
      }
    )
  }
}

# ─────────────────────────────────────────
# Auto Scaling Group - Frontend
# ─────────────────────────────────────────
resource "aws_autoscaling_group" "frontend_asg" {
  desired_capacity = var.desired_capacity
  max_size         = var.max_size
  min_size         = var.min_size

  vpc_zone_identifier = var.public_subnets

  launch_template {
    id      = aws_launch_template.frontend_lt.id
    version = "$Latest"
  }

  health_check_type = "EC2"

  tag {
    key                 = "Name"
    value               = "arquisoft-frontend-asg"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = lookup(var.tags, "Project", "arquisoft")
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = lookup(var.tags, "Environment", "dev")
    propagate_at_launch = true
  }
}
