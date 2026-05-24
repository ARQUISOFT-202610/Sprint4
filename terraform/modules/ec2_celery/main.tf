# ─────────────────────────────────────────
# Security Group - Celery Workers
# ─────────────────────────────────────────
resource "aws_security_group" "celery_sg" {
  name        = "arquisoft-celery-sg"
  description = "Allow traffic for Celery workers"
  vpc_id      = var.vpc_id

  # SSH Access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access from anywhere"
  }

  # Flower UI (optional, for monitoring)
  ingress {
    from_port   = 5555
    to_port     = 5555
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Flower UI for Celery monitoring"
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
      Name = "arquisoft-celery-sg"
    }
  )
}

# ─────────────────────────────────────────
# Launch Template - Celery Workers
# ─────────────────────────────────────────
resource "aws_launch_template" "celery_lt" {
  name_prefix   = "celery-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  key_name = var.key_name

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.celery_sg.id]
  }

  iam_instance_profile {
    name = var.iam_instance_profile
  }

  user_data = base64encode(templatefile("${path.module}/../../scripts/celery_setup.sh", {
    github_token = var.github_token
    env_file     = var.env_file
  }))

  tag_specifications {
    resource_type = "instance"

    tags = merge(
      var.tags,
      {
        Name = "arquisoft-celery-worker"
      }
    )
  }
}

# ─────────────────────────────────────────
# Auto Scaling Group - Celery Workers
# ─────────────────────────────────────────
resource "aws_autoscaling_group" "celery_asg" {
  desired_capacity = var.desired_capacity
  max_size         = var.max_size
  min_size         = var.min_size

  vpc_zone_identifier = var.public_subnets

  launch_template {
    id      = aws_launch_template.celery_lt.id
    version = "$Latest"
  }

  health_check_type = "EC2"

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["tag"]
  }

  tag {
    key                 = "Name"
    value               = "arquisoft-celery-asg"
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
