# ─────────────────────────────────────────
# Security Group - FastAPI EC2
# ─────────────────────────────────────────
resource "aws_security_group" "fastapi_sg" {
  name        = "arquisoft-fastapi-ec2-sg"
  description = "Allow traffic from ALB, DynamoDB communication, and SSH"
  vpc_id      = var.vpc_id

  # Traffic from ALB to FastAPI
  ingress {
    from_port       = 8001
    to_port         = 8001
    protocol        = "tcp"
    security_groups = [var.alb_sg_id]
  }

  # SSH Access (port 22) - for debugging and management
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access from anywhere"
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
      Name = "arquisoft-fastapi-ec2-sg"
    }
  )
}

# ─────────────────────────────────────────
# Launch Template - FastAPI
# ─────────────────────────────────────────
resource "aws_launch_template" "fastapi_lt" {
  name_prefix   = "fastapi-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  key_name = var.key_name

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.fastapi_sg.id]
  }

  iam_instance_profile {
    name = var.iam_instance_profile
  }

  user_data = base64encode(templatefile("${path.module}/../../scripts/fastapi_setup.sh", {
    github_token = var.github_token
    env_file     = var.env_file
  }))

  tags = merge(
    var.tags,
    {
      Name = "arquisoft-fastapi-lt"
    }
  )

  tag_specifications {
    resource_type = "instance"

    tags = merge(
      var.tags,
      {
        Name = "fastapi-instance"
      }
    )
  }
}

# ─────────────────────────────────────────
# Auto Scaling Group - FastAPI
# ─────────────────────────────────────────
resource "aws_autoscaling_group" "fastapi_asg" {
  desired_capacity = var.desired_capacity
  max_size         = var.max_size
  min_size         = var.min_size

  vpc_zone_identifier = var.public_subnets

  launch_template {
    id      = aws_launch_template.fastapi_lt.id
    version = "$Latest"
  }

  target_group_arns = [var.target_group_arn]

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
    value               = "arquisoft-fastapi-ec2"
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
