# ─────────────────────────────────────────
# Subnet Group (RDS en subredes privadas)
# ─────────────────────────────────────────
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = var.private_subnets

  tags = {
    Name = "arquisoft-rds-subnet-group"
  }
}

# ─────────────────────────────────────────
# Security Group para RDS
# ─────────────────────────────────────────
resource "aws_security_group" "rds_sg" {
  name        = "arquisoft-rds-sg"
  description = "Allow PostgreSQL access from Django and Celery"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.allowed_sg_ids
    content {
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [ingress.value]
      description     = "PostgreSQL from EC2"
    }
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
      Name = "arquisoft-rds-sg"
    }
  )
}

# ─────────────────────────────────────────
# RDS PostgreSQL Instance
# ─────────────────────────────────────────
resource "aws_db_instance" "postgres" {
  identifier = "arquisoft-django-db"

  engine         = "postgres"
  engine_version = "17.7"
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  # High Availability: Multi-AZ enabled
  multi_az = var.multi_az

  # Backup and maintenance
  publicly_accessible     = false
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"
  skip_final_snapshot     = true
  deletion_protection     = false
  storage_encrypted       = false # Can be enabled for production

  # Performance insights (optional)
  performance_insights_enabled = false

  tags = merge(
    var.tags,
    {
      Name = "arquisoft-rds-postgres"
    }
  )
}