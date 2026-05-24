# ─────────────────────────────────────────
# Security Group - DynamoDB Local EC2
# ─────────────────────────────────────────
resource "aws_security_group" "dynamodb_sg" {
  name        = "arquisoft-dynamodb-ec2-sg"
  description = "Allow DynamoDB Local communication and SSH"
  vpc_id      = var.vpc_id

  # DynamoDB Local port (8000) - will be restricted by rule from FastAPI
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "DynamoDB Local access"
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
      Name = "arquisoft-dynamodb-ec2-sg"
    }
  )
}

# ─────────────────────────────────────────
# EC2 Instance - DynamoDB Local
# ─────────────────────────────────────────
resource "aws_instance" "dynamodb" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  associate_public_ip_address = true
  subnet_id                   = var.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.dynamodb_sg.id]
  iam_instance_profile        = var.iam_instance_profile

  user_data_base64 = base64encode(templatefile("${path.module}/../../scripts/dynamodb_setup.sh", {
    env_file = var.env_file
  }))

  tags = merge(
    var.tags,
    {
      Name = "arquisoft-dynamodb-local"
    }
  )
}
