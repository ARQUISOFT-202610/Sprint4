# Arquisoft - Django AWS Infrastructure Project

Enterprise-grade Django application deployed on AWS using Terraform infrastructure as code.

## Project Overview

This project is a production-ready Django application with:
- **Backend**: Django 5.x with Celery for async tasks
- **Infrastructure**: AWS (EC2, RDS, ElastiCache, SQS, ALB)
- **Deployment**: Terraform modules with modular architecture

## Architecture

```
                              ┌─────────────────┐
                              │   Internet      │
                              └────────┬────────┘
                                       │
                              ┌────────▼────────┐
                              │  Application    │
                              │  Load Balancer  │
                              │    (ALB)        │
                              └────────┬────────┘
                                       │
                              ┌────────▼────────┐
                              │  Django EC2     │
                              │  (Auto Scaling) │
                              └────────┬────────┘
                                       │
              ┌────────────────────────┼────────────────────────┐
              │                        │                        │
     ┌────────▼────────┐      ┌────────▼────────┐      ┌────────▼────────┐
     │   RDS           │      │   ElastiCache   │      │   SQS           │
     │   PostgreSQL    │      │   Redis         │      │   Celery Tasks  │
     └─────────────────┘      └─────────────────┘      └─────────────────┘
              │                        │                        │
              │                        │                        │
     ┌────────▼────────┐      ┌────────▼────────┐      ┌────────▼────────┐
     │  Celery Workers │      │  Celery Workers │      │  Celery Workers │
     │  (EC2 ASG)      │      │  (EC2 ASG)      │      │  (EC2 ASG)      │
     └─────────────────┘      └─────────────────┘      └─────────────────┘
```

## Directory Structure

```
Sprint3/
├── backend/                    # Django application
│   ├── application/            # Use cases and DTOs
│   ├── core/                  # Entities and exceptions
│   ├── config/                # Django settings (base, dev, prod)
│   ├── infrastructure/        # External services (email, cache, queue)
│   ├── interfaces/            # API views, serializers, permissions
│   ├── requirements/          # pip dependencies
│   ├── scripts/               # Testing and maintenance scripts
│   └── Dockerfile             # Production container
│
├── terraform/                  # AWS Infrastructure (Terraform)
│   ├── main.tf                # Root module - resource orchestration
│   ├── variables.tf           # Input variables
│   ├── outputs.tf             # Output values
│   ├── provider.tf            # AWS provider configuration
│   ├── terraform.tfvars       # Variable values
│   ├── modules/               # Reusable Terraform modules
│   │   ├── alb/               # Application Load Balancer
│   │   ├── network/           # VPC, subnets, routing
│   │   ├── rds/               # PostgreSQL database
│   │   ├── redis/             # ElastiCache cluster
│   │   ├── sqs/              # Simple Queue Service
│   │   ├── ec2_django/        # Django EC2 instances + ASG
│   │   ├── ec2_celery/        # Celery workers + ASG
│   │   ├── ec2_frontend/      # Frontend EC2 instances + ASG
│   │   └── iam/               # Roles and instance profiles
│   └── scripts/               # EC2 user data scripts
│
├── .gitignore                 # Git ignore rules
└── README.md                  # This file
```

## Prerequisites

- **AWS Account** with appropriate permissions
- **Terraform** >= 1.0 (installed locally)
- **Python** >= 3.12 (for Django)
- **AWS CLI** (configured with credentials)

## Quick Start

### 1. Configure Environment

```bash
# Copy example environment file
cp backend/.env.example backend/.env

# Edit with your settings
nano backend/.env
```

### 2. Deploy Infrastructure (Terraform)

```bash
cd terraform

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply changes (creates all AWS resources)
terraform apply
```

### 3. Deploy Django Application

The Django app is deployed automatically via EC2 user_data scripts. After Terraform completes:

```bash
# Check Django status (SSH to EC2)
ssh -i your-key.pem ubuntu@<django-ec2-ip>
sudo systemctl status gunicorn
```

## Terraform Modules

| Module | Description |
|--------|-------------|
| `alb` | Application Load Balancer for Django |
| `network` | VPC, subnets, internet gateway, routing |
| `rds` | PostgreSQL RDS instance |
| `redis` | ElastiCache Redis cluster |
| `sqs` | Celery task queue |
| `ec2_django` | Django web servers (Auto Scaling) |
| `ec2_celery` | Celery background workers |
| `ec2_frontend` | Nginx + React frontend |
| `iam` | IAM roles and instance profiles |

## Available Outputs

After `terraform apply`, use these outputs:

```bash
# Application URL
terraform output django_alb_dns_name

# Database endpoint
terraform output rds_endpoint

# Redis endpoint
terraform output redis_endpoint

# Full infrastructure summary
terraform output infrastructure_summary
```

## Configuration

### Terraform Variables (`terraform/terraform.tfvars`)

```hcl
project_name    = "arquisoft"
environment     = "prod"
region          = "us-east-1"
key_name        = "your-ssh-key"
github_token    = "ghp_..."
db_password     = "secure-password"
ami_id          = ""  # Leave empty for default Ubuntu AMI
```

### Django Settings

Edit `backend/config/settings/production.py` for production-specific configuration.

## Maintenance

### Update Infrastructure

```bash
cd terraform
terraform plan    # Review changes
terraform apply   # Apply updates
```

### Troubleshooting

```bash
# View Django logs
ssh ubuntu@<instance> "sudo journalctl -u gunicorn -f"

# View Celery logs
ssh ubuntu@<celery-instance> "sudo journalctl -u celery -f"

# Test connectivity
python backend/scripts/test_db.py
python backend/scripts/test_redis.py
python backend/scripts/test_sqs.py
```

## Development

### Local Development with Docker

```bash
cd backend
docker-compose -f docker-compose.local.yml up --build
```

### Run Tests

```bash
cd backend
python manage.py test
python scripts/test_full_stack.py
```

## Security Notes

- **Never commit** `.env` files or AWS credentials
- **Rotate** SSH keys and database passwords regularly
- **Use** IAM roles with minimal required permissions
- **Enable** deletion protection for RDS and ALB in production

## License

This project is for educational and production use.