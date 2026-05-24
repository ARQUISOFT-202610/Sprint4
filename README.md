# Arquisoft - AWS Infrastructure Project

Enterprise-grade multi-service infrastructure deployed on AWS using Terraform infrastructure as code. Includes Django backend, FastAPI microservice, React frontend, Celery workers, and DynamoDB local storage.

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Infrastructure Components](#infrastructure-components)
4. [Directory Structure](#directory-structure)
5. [Deployment Overview](#deployment-overview)
6. [Services and Ports](#services-and-ports)
7. [API Endpoints](#api-endpoints)
8. [Prerequisites](#prerequisites)
9. [Quick Start](#quick-start)
10. [Terraform Modules](#terraform-modules)
11. [Configuration](#configuration)
12. [Deployment Instructions](#deployment-instructions)
13. [Accessing Services](#accessing-services)
14. [Troubleshooting](#troubleshooting)
15. [Security Considerations](#security-considerations)

---

## Project Overview

This project is a production-ready distributed system architecture deployed on AWS with:

- **Backend API**: Django 5.x REST API with Gunicorn server
- **Microservices**: FastAPI application for specialized workloads
- **Frontend**: React single-page application served via Nginx with HTTPS
- **Async Tasks**: Celery workers with Flower monitoring dashboard
- **Data Storage**: PostgreSQL RDS database, DynamoDB local instance
- **Message Queue**: SQS for Celery task distribution
- **Load Balancing**: Application Load Balancer with path-based routing
- **Infrastructure as Code**: Terraform modules for AWS resource management

---

## Architecture

### High-Level System Diagram

```
                            ┌──────────────────┐
                            │   Internet       │
                            │   (HTTPS)        │
                            └────────┬─────────┘
                                     │
                            ┌────────▼─────────┐
                            │   Application    │
                            │   Load Balancer  │
                            │   (Port 80/443)  │
                            └────────┬─────────┘
                                     │
                    ┌────────────────┼────────────────┐
                    │                │                │
           ┌────────▼────────┐  ┌────▼─────┐  ┌──────▼──────┐
           │ Django Backend  │  │ FastAPI   │  │ React Nginx │
           │ (Port 8000)     │  │ (Port 8001)  │ (Port 443)  │
           │ Auto Scaling    │  │ Auto Scale  │ (Redirect 80)
           └────────┬────────┘  └────┬─────┘  └─────────────┘
                    │                │
        ┌───────────┼────────────┐   │
        │           │            │   │
   ┌────▼───┐  ┌────▼───┐  ┌────▼────┐
   │   RDS  │  │   SQS  │  │ DynamoDB│
   │  DB    │  │ Tasks  │  │ (Local) │
   └────────┘  └────┬───┘  └─────────┘
                    │
              ┌─────▼─────┐
              │  Celery   │
              │  Workers  │
              │ + Flower  │
              └───────────┘
```

### Network Architecture

```
AWS Region: us-east-1
├── VPC (10.0.0.0/16)
│   ├── Public Subnets (for ALB, Frontend, NAT)
│   │   ├── us-east-1a: 10.0.1.0/24
│   │   └── us-east-1b: 10.0.2.0/24
│   ├── Private Subnets (for RDS, Internal services)
│   │   ├── us-east-1a: 10.0.10.0/24
│   │   └── us-east-1b: 10.0.11.0/24
│   └── Internet Gateway
│       └── NAT Gateway (for private subnet egress)
```

---

## Infrastructure Components

### Compute Services

1. **Django Web Servers**
   - Instance Type: t2.micro (configurable)
   - Auto Scaling: 1-4 instances
   - Regions: us-east-1a + us-east-1b (multi-AZ)
   - Port: 8000 (internal, behind ALB)
   - Framework: Django 5.x + Gunicorn

2. **FastAPI Application**
   - Instance Type: t2.micro (configurable)
   - Auto Scaling: 1-3 instances
   - Regions: us-east-1a + us-east-1b (multi-AZ)
   - Port: 8001 (internal, behind ALB)
   - Framework: FastAPI + Uvicorn
   - Purpose: Specialized microservice workloads

3. **Celery Workers**
   - Instance Type: t2.micro (configurable)
   - Auto Scaling: 1-4 instances
   - Concurrency: 4 workers per instance
   - Task Queue: SQS
   - Monitoring: Flower dashboard (port 5555)

4. **Frontend Server**
   - Instance Type: t2.micro (configurable)
   - Quantity: 1 instance
   - Region: us-east-1a
   - Port: 443 (HTTPS), 80 (HTTP redirect)
   - Server: Nginx
   - Frontend: React SPA

5. **DynamoDB Local Instance**
   - Instance Type: t2.micro
   - Quantity: 1 instance
   - Port: 8000 (internal)
   - Purpose: Local DynamoDB for development/testing
   - Logging: Local only (no CloudWatch)

### Database Services

1. **PostgreSQL RDS**
   - Multi-AZ: Enabled
   - Instance Type: db.t3.micro
   - Engine: PostgreSQL 14+
   - Port: 5432 (internal)
   - Backup: Automated 7-day retention
   - Encryption: Enabled

2. **SQS Queue**
   - Queue Name: arquisoft-celery-tasks
   - Visibility Timeout: 300 seconds
   - Message Retention: 4 days
   - Purpose: Celery task distribution

### Load Balancing

1. **Application Load Balancer (ALB)**
   - Port: 80 (HTTP)
   - Port: 443 (HTTPS)
   - Target Groups:
     - Django: arquisoft-alb-django-tg (port 8000)
     - FastAPI: arquisoft-alb-fastapi-tg (port 8001)
   - Health Checks: 30-second intervals
   - Routing: Path-based (/api/* -> Django, /fastapi/* -> FastAPI)

### Security

1. **Security Groups**
   - ALB Security Group: Allows HTTP/HTTPS from anywhere
   - Django Security Group: Allows port 8000 from ALB
   - FastAPI Security Group: Allows port 8001 from ALB
   - RDS Security Group: Allows port 5432 from Django/Celery
   - Celery Security Group: Allows port 5432 from RDS

2. **Network Access**
   - Public Subnets: ALB, Frontend, NAT Gateway
   - Private Subnets: RDS (protected)
   - SSH Access: Configurable via security groups

---

## Directory Structure

```
Sprint4/
├── backend/                          # Django Application
│   ├── config/                       # Django configuration
│   │   ├── django_settings.py        # Main Django settings
│   │   ├── wsgi.py                   # WSGI entry point
│   │   └── urls.py                   # URL routing
│   ├── application/                  # Business logic
│   │   ├── services/                 # Application services
│   │   ├── dto/                      # Data transfer objects
│   │   └── usecases/                 # Use case implementations
│   ├── core/                         # Domain entities
│   │   ├── models/                   # Core domain models
│   │   └── exceptions/               # Custom exceptions
│   ├── infrastructure/               # External services integration
│   │   ├── email/                    # SES email service
│   │   ├── cache/                    # Cache service
│   │   ├── queue/                    # SQS queue service
│   │   └── database/                 # Database connections
│   ├── interfaces/                   # API interfaces
│   │   ├── views/                    # Django REST views
│   │   ├── serializers/              # DRF serializers
│   │   ├── permissions/              # Custom permissions
│   │   └── middleware/               # Custom middleware
│   ├── manage.py                     # Django management script
│   ├── requirements.txt              # Python dependencies
│   ├── .env.example                  # Environment file template
│   ├── Dockerfile                    # Container image definition
│   └── docker-compose.yml            # Local development setup
│
├── frontend/                         # React Application
│   ├── public/                       # Static assets
│   ├── src/
│   │   ├── components/               # React components
│   │   ├── pages/                    # Page components
│   │   ├── services/                 # API service client
│   │   ├── hooks/                    # Custom React hooks
│   │   ├── App.js                    # Root component
│   │   └── index.js                  # React entry point
│   ├── package.json                  # Node.js dependencies
│   └── Dockerfile                    # Frontend container
│
├── terraform/                        # AWS Infrastructure
│   ├── main.tf                       # Root module configuration
│   ├── variables.tf                  # Input variables
│   ├── outputs.tf                    # Output values
│   ├── provider.tf                   # AWS provider setup
│   ├── terraform.tfvars              # Variable values (local)
│   ├── terraform.tfvars.example      # Variable template
│   ├── .terraform.lock.hcl           # Dependency lock file
│   │
│   ├── modules/                      # Reusable Terraform modules
│   │   ├── network/
│   │   │   ├── main.tf               # VPC, subnets, gateways
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   ├── alb/
│   │   │   ├── main.tf               # Application Load Balancer
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   ├── rds/
│   │   │   ├── main.tf               # PostgreSQL database
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   ├── sqs/
│   │   │   ├── main.tf               # SQS queue
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   ├── ec2_django/
│   │   │   ├── main.tf               # Django servers + ASG
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   ├── ec2_fastapi/
│   │   │   ├── main.tf               # FastAPI servers + ASG
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   ├── ec2_celery/
│   │   │   ├── main.tf               # Celery workers + ASG
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   ├── ec2_dynamodb/
│   │   │   ├── main.tf               # DynamoDB local instance
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   ├── ec2_frontend/
│   │   │   ├── main.tf               # Frontend nginx server
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   ├── ec2_keypair/
│   │   │   ├── main.tf               # SSH key pair
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   ├── tls_certificate/
│   │   │   ├── main.tf               # Self-signed SSL cert
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   ├── cloudwatch/
│   │   │   ├── main.tf               # CloudWatch log groups
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   └── ses/
│   │       ├── main.tf               # Email service setup
│   │       ├── variables.tf
│   │       └── outputs.tf
│   │
│   ├── scripts/                      # EC2 user-data scripts
│   │   ├── django_setup.sh           # Django deployment script
│   │   ├── fastapi_setup.sh          # FastAPI deployment script
│   │   ├── celery_setup.sh           # Celery deployment script
│   │   ├── frontend_deploy.sh        # Frontend deployment script
│   │   ├── dynamodb_setup.sh         # DynamoDB local setup
│   │   └── install_tf.sh             # Terraform CLI setup
│   │
│   └── MANUAL_STEPS.md               # Post-deployment guide (SES setup)
│
├── tests/
│   ├── jmeter/                       # Performance testing
│   │   ├── load_test.jmx            # JMeter test plan
│   │   └── results/
│   │
│   └── integration/                  # Integration tests
│       └── test_endpoints.py
│
├── .gitignore                        # Git ignore rules
├── .env.example                      # Environment template
├── README.md                         # This file
└── LICENSE                           # Project license
```

---

## Deployment Overview

### Deployment Architecture

When `terraform apply` is executed, the following resources are created:

1. **Networking** (VPC, Subnets, Gateways)
2. **Security Groups** (ALB, EC2, RDS)
3. **SSL/TLS Certificate** (Self-signed for HTTPS)
4. **SSH Key Pair** (For EC2 access)
5. **RDS Database** (PostgreSQL)
6. **SQS Queue** (For Celery tasks)
7. **Load Balancer** (with target groups and listeners)
8. **EC2 Instances** (Django, FastAPI, Celery, Frontend, DynamoDB)
9. **Auto Scaling Groups** (for Django, FastAPI, Celery)
10. **CloudWatch Log Groups** (for audit logging)

### Auto Scaling Configuration

| Service | Min | Desired | Max | Metric | Threshold |
|---------|-----|---------|-----|--------|-----------|
| Django | 1 | 2 | 4 | CPU > 70% | scale up |
| FastAPI | 1 | 2 | 3 | CPU > 70% | scale up |
| Celery | 1 | 2 | 4 | CPU > 70% | scale up |
| Frontend | 1 | 1 | 1 | N/A | N/A |

---

## Services and Ports

### Internal Service Ports (ALB/VPC)

| Service | Port | Protocol | Purpose |
|---------|------|----------|---------|
| Django (Gunicorn) | 8000 | HTTP | Backend API server |
| FastAPI (Uvicorn) | 8001 | HTTP | Microservice API server |
| DynamoDB Local | 8000 | HTTP | Local data storage (internal) |
| Celery Flower | 5555 | HTTP | Task monitoring dashboard |
| RDS PostgreSQL | 5432 | TCP | Database server |
| SQS | - | AWS API | Message queue service |

### External Service Ports (Internet)

| Service | Port | Protocol | Purpose |
|---------|------|----------|---------|
| HTTP | 80 | HTTP | Redirect to HTTPS |
| HTTPS | 443 | HTTPS | Frontend React app |
| ALB | 80/443 | HTTP/HTTPS | Load balancer endpoints |

### Access Points

| Component | URL | Port | Auth | Purpose |
|-----------|-----|------|------|---------|
| Frontend React App | https://\<alb-dns\> | 443 | None | User interface |
| Django API | https://\<alb-dns\>/api | 443 | Token | REST API |
| FastAPI | https://\<alb-dns\>/fastapi | 443 | Token | Specialized API |
| Celery Flower | https://\<django-ip\>:5555 | 5555 | None | Task monitoring |
| Database | \<rds-endpoint\>:5432 | 5432 | Credentials | PostgreSQL |

---

## API Endpoints

### Django REST API

All endpoints are behind the ALB at `https://<alb-dns>/api/`

#### Authentication
- **POST** `/api/auth/login/` - User login
- **POST** `/api/auth/logout/` - User logout
- **POST** `/api/auth/refresh/` - Refresh token
- **POST** `/api/auth/register/` - User registration

#### User Management
- **GET** `/api/users/` - List all users (admin only)
- **POST** `/api/users/` - Create user
- **GET** `/api/users/{id}/` - Get user details
- **PUT** `/api/users/{id}/` - Update user
- **DELETE** `/api/users/{id}/` - Delete user

#### Core Resources (example endpoints)
- **GET** `/api/resources/` - List resources
- **POST** `/api/resources/` - Create resource
- **GET** `/api/resources/{id}/` - Get resource details
- **PUT** `/api/resources/{id}/` - Update resource
- **DELETE** `/api/resources/{id}/` - Delete resource

#### Health & Status
- **GET** `/health/` - Health check endpoint
- **GET** `/api/status/` - System status

### FastAPI Endpoints

All endpoints are behind the ALB at `https://<alb-dns>/fastapi/`

#### Health & Status
- **GET** `/fastapi/health` - Health check
- **GET** `/fastapi/status` - Service status

#### Core Endpoints
- **GET** `/fastapi/items/` - List items
- **POST** `/fastapi/items/` - Create item
- **GET** `/fastapi/items/{id}` - Get item details
- **PUT** `/fastapi/items/{id}` - Update item
- **DELETE** `/fastapi/items/{id}` - Delete item

#### WebSocket (if implemented)
- **WS** `/fastapi/ws` - WebSocket connection

### Celery/Flower Monitoring

- **GET** `http://<celery-ip>:5555/` - Flower dashboard
- **API** `http://<celery-ip>:5555/api/` - Flower REST API

---

## Prerequisites

### Local Development

- **Terraform** >= 1.5.0
- **Python** >= 3.12
- **Node.js** >= 18.x
- **Docker** and **Docker Compose** (optional)
- **AWS CLI** v2 (configured with credentials)
- **Git**

### AWS Account

- Active AWS account with appropriate IAM permissions
- AWS Academy Learner Lab account (if using Academy)
- SSH key pair for EC2 access

### Credentials

- GitHub personal access token (for repository cloning)
- AWS credentials with permissions for:
  - EC2, RDS, VPC, SQS, ALB, CloudWatch, SES
  - IAM (read-only, LabInstanceProfile)

---

## Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/ARQUISOFT-202610/Sprint4.git
cd Sprint4
```

### 2. Configure Terraform

```bash
cd terraform

# Copy example variables
cp terraform.tfvars.example terraform.tfvars

# Edit with your settings
nano terraform.tfvars
```

Required variables in `terraform.tfvars`:
```hcl
project_name      = "arquisoft"
environment        = "dev"
region             = "us-east-1"
key_name           = "your-ssh-key-name"
github_token       = "ghp_xxxxxxxxxxxxx"  # GitHub personal access token
db_password        = "strong-password-123"
recipient_email    = "user@example.com"
ami_id             = ""  # Leave empty for default Ubuntu
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Review Deployment Plan

```bash
terraform plan
```

Review the output to verify all resources that will be created.

### 5. Deploy Infrastructure

```bash
terraform apply
```

Confirm by typing `yes` when prompted. Deployment takes 5-15 minutes.

### 6. Retrieve Outputs

```bash
# Get ALB DNS name (main entry point)
terraform output alb_dns_name

# Get RDS endpoint
terraform output rds_endpoint

# Get all outputs
terraform output
```

---

## Terraform Modules

### Module Overview

| Module | Purpose | Resources | Output |
|--------|---------|-----------|--------|
| `network` | VPC networking | VPC, Subnets, IGW, NAT | VPC ID, Subnet IDs |
| `alb` | Load balancing | ALB, Target Groups, Listeners | ALB DNS, TG ARNs |
| `rds` | Database | RDS Instance, Security Group | DB Endpoint, Credentials |
| `sqs` | Message queue | SQS Queue | Queue URL, Queue Name |
| `ec2_django` | Django servers | Launch Template, ASG | Instance IDs |
| `ec2_fastapi` | FastAPI servers | Launch Template, ASG | Instance IDs |
| `ec2_celery` | Celery workers | Launch Template, ASG | Instance IDs |
| `ec2_dynamodb` | DynamoDB local | EC2 Instance | Private IP |
| `ec2_frontend` | Frontend server | EC2 Instance, Nginx | Instance IP |
| `ec2_keypair` | SSH key | Key Pair | Key Name |
| `tls_certificate` | SSL certificate | Self-signed Certificate | Certificate PEM |
| `cloudwatch` | Logging | Log Groups | Log Group Names |
| `ses` | Email service | SES Identities, Templates | Sender Email |

---

## Configuration

### Terraform Variables (`terraform/terraform.tfvars`)

```hcl
# Project identification
project_name      = "arquisoft"
environment        = "dev"
region             = "us-east-1"

# SSH Access
key_name           = "arquisoft-key"

# GitHub
github_token       = "ghp_your_token_here"

# Database
db_password        = "your-secure-password"

# Email
recipient_email    = "notifications@example.com"

# AMI (leave empty for default)
ami_id             = ""

# Instance sizing (optional)
django_instance_type  = "t2.micro"
fastapi_instance_type = "t2.micro"
celery_instance_type  = "t2.micro"
```

### Django Environment (`.env` file)

Created automatically by Terraform with values for:
- Database connection (RDS endpoint, credentials)
- SQS queue URL and region
- CloudWatch log groups
- SES email configuration
- AWS region

---

## Deployment Instructions

### Step-by-Step Deployment

#### Step 1: Prepare AWS Environment

```bash
# Ensure you're in the correct AWS account
aws sts get-caller-identity

# Verify S3 bucket exists for Terraform state (optional)
aws s3 ls
```

#### Step 2: Initialize Terraform

```bash
cd terraform
terraform init

# Verify initialization
terraform validate
```

#### Step 3: Plan Deployment

```bash
terraform plan -out=tfplan

# Save plan for later review
terraform show tfplan | tee tfplan.txt
```

#### Step 4: Deploy Infrastructure

```bash
# Apply the plan (creates all AWS resources)
terraform apply tfplan

# Wait 10-15 minutes for all instances to be ready
```

#### Step 5: Verify Deployment

```bash
# Get ALB DNS
ALB_DNS=$(terraform output -raw alb_dns_name)
echo "Frontend URL: https://$ALB_DNS"

# Test health endpoints
curl -k https://$ALB_DNS/health/
curl -k https://$ALB_DNS/api/status/
```

#### Step 6: Monitor Instance Setup

```bash
# Get Django instance IP
DJANGO_IP=$(terraform output -raw django_instance_ips | head -1)

# SSH into instance and check service status
ssh -i /path/to/key.pem ubuntu@$DJANGO_IP

# Inside instance:
sudo journalctl -u gunicorn -f  # Django logs
sudo journalctl -u celery -f    # Celery logs
sudo systemctl status gunicorn  # Service status
```

### Scaling Services

To change instance counts or sizes:

```bash
# Edit terraform.tfvars
nano terraform.tfvars

# Update desired_capacity, max_size, or instance_type
# Example:
# desired_capacity = 3  # Scale to 3 instances

# Apply changes
terraform plan
terraform apply
```

### Updating Services

```bash
# For backend updates:
# 1. Push changes to GitHub
# 2. SSH to Django instance
# 3. Pull latest code:
cd /app && git pull

# 4. Reinstall dependencies if needed:
/app/venv/bin/pip install -r backend/requirements.txt

# 5. Run migrations:
/app/venv/bin/python backend/manage.py migrate

# 6. Restart service:
sudo systemctl restart gunicorn
```

---

## Accessing Services

### SSH Access to Instances

```bash
# Get instance IPs
terraform output instance_ips

# SSH to Django instance
ssh -i /path/to/key.pem ubuntu@<django-ip>

# SSH to Frontend instance
ssh -i /path/to/key.pem ubuntu@<frontend-ip>

# SSH to Celery instance
ssh -i /path/to/key.pem ubuntu@<celery-ip>
```

### Web Access

```bash
# Get ALB DNS name
ALB_DNS=$(terraform output -raw alb_dns_name)

# Frontend (React app)
# Note: Uses self-signed certificate
open "https://$ALB_DNS"

# API endpoints
curl -k https://$ALB_DNS/api/status/

# FastAPI endpoint
curl -k https://$ALB_DNS/fastapi/health

# Celery Flower (requires SSH port forward)
ssh -i key.pem -L 5555:localhost:5555 ubuntu@<celery-ip>
# Then: open http://localhost:5555
```

### Database Access

```bash
# Get RDS endpoint
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)

# Connect with psql (from your local machine)
# First, create SSH tunnel:
ssh -i key.pem -L 5432:$RDS_ENDPOINT:5432 ubuntu@<django-ip>

# In another terminal:
psql -h localhost -U arquisoft -d arquisoft -W
# Password: (value from terraform.tfvars)
```

### Service Health Checks

```bash
# Django health check
curl -k https://$ALB_DNS/health/

# FastAPI health check
curl -k https://$ALB_DNS/fastapi/health

# RDS connectivity (from Django instance)
ssh ubuntu@<django-ip> 'PGPASSWORD=password psql -h <rds-endpoint> -U arquisoft -d arquisoft -c "SELECT 1;"'

# SQS queue status (from Celery instance)
ssh ubuntu@<celery-ip> 'aws sqs get-queue-attributes --queue-url $AWS_SQS_URL --attribute-names All'
```

---

## Troubleshooting

### Common Issues

#### Instances Marked Unhealthy by ALB

**Problem:** Instances are in "unhealthy" state in ALB target groups

**Solution:**
```bash
# SSH to instance
ssh ubuntu@<instance-ip>

# Check service status
sudo systemctl status gunicorn
sudo systemctl status fastapi
sudo journalctl -u gunicorn -n 50

# Check if service is listening
sudo ss -tulpn | grep 8000

# View application logs
sudo journalctl -u gunicorn -f

# Restart service if needed
sudo systemctl restart gunicorn
```

#### Git Clone Failed During Setup

**Problem:** Repository clone fails during EC2 instance initialization

**Solution:**
```bash
# This is usually a transient network issue
# The setup script has retry logic (3 attempts)

# If still failing, manually clone:
ssh ubuntu@<instance-ip>
sudo su - ubuntu
git clone https://x-access-token:<TOKEN>@github.com/ARQUISOFT-202610/Sprint4.git /app
```

#### Database Connection Issues

**Problem:** Django instances cannot connect to RDS

**Solution:**
```bash
# Verify RDS is ready
terraform output rds_endpoint

# Check security group rules (RDS should allow port 5432 from Django SG)
aws ec2 describe-security-groups --filters Name=group-name,Values=arquisoft-rds-sg

# Test connectivity from Django instance
ssh ubuntu@<django-ip>
PGPASSWORD=<password> psql -h <rds-endpoint> -U arquisoft -d arquisoft -c "SELECT 1;"
```

#### ALB Cannot Find Backend Instances

**Problem:** ALB returns 503 Service Unavailable

**Solution:**
```bash
# Check target group health
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn> \
  --region us-east-1

# Look for Status=unhealthy
# Usually caused by instances not finishing setup
# Wait 5-10 minutes for setup to complete
```

#### Logs Not Appearing

**Problem:** Setup logs not visible

**Solution:**
```bash
# Logs are now available via systemd journalctl (not CloudWatch)
ssh ubuntu@<instance-ip>

# View all logs
sudo journalctl -u gunicorn

# Follow logs in real-time
sudo journalctl -u gunicorn -f

# View setup logs
cat /var/log/user-data.log
```

### Debugging Commands

```bash
# Check instance metadata
ssh ubuntu@<instance> "curl http://169.254.169.254/latest/meta-data/instance-id"

# Check security groups
aws ec2 describe-security-groups \
  --filters Name=group-name,Values=arquisoft-django-ec2-sg

# View Auto Scaling Group details
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names arquisoft-django-asg

# Check target group registration
aws elbv2 describe-target-health \
  --target-group-arn <arn>
```

---

## Security Considerations

### Network Security

- All instances are in VPC with no direct internet access (except via ALB)
- RDS is in private subnet, only accessible from Django/Celery security groups
- SSH access is via security group rules (configure as needed)
- ALB enforces HTTPS (443) with SSL/TLS termination

### Database Security

- RDS has automated backups (7-day retention)
- Database password is environment-specific
- Consider enabling encryption at rest for production
- Database credentials stored in EC2 environment only

### Application Security

- Django `DEBUG` mode is configurable (set to False in production)
- API endpoints require proper authentication (implement JWT/OAuth)
- CORS headers should be configured for cross-origin requests
- Rate limiting recommended on production

### AWS IAM

- Uses AWS Academy `LabInstanceProfile` (read-only permissions)
- No custom IAM roles created
- Credentials managed via instance profile
- SSH keys stored in AWS Secrets Manager (recommended for production)

### SSL/TLS

- Self-signed certificate for HTTPS
- Valid for 1 year (rotate after expiration)
- For production, replace with proper certificate from ACM
- ALB performs SSL/TLS termination

### Secrets Management

- GitHub token stored in Terraform (use AWS Secrets Manager in production)
- Database password in terraform.tfvars (use tfvars.local or Terraform Cloud)
- Environment variables passed via user-data (consider Secrets Manager)

### Compliance

- CloudWatch Log Groups retain logs for 90 days
- Audit logs available in /arquisoft/*/security log streams
- Implement additional compliance controls as needed
- Review AWS Security Hub for security recommendations

---

## Post-Deployment Steps

### Manual Configuration (SES Email Service)

For production email notifications:

1. **Verify SES Identities** (Console or AWS CLI)
2. **Create Email Templates** (see terraform/MANUAL_STEPS.md)
3. **Request Production Access** (SES sandbox limits)
4. **Configure Notification Recipients** in Django settings

See `terraform/MANUAL_STEPS.md` for detailed SES setup instructions.

### Monitoring Setup

```bash
# Access CloudWatch Logs
aws logs describe-log-groups --log-group-name-prefix /arquisoft

# View recent logs
aws logs tail /arquisoft/django --follow

# Set up CloudWatch alarms (recommended)
aws cloudwatch put-metric-alarm ...
```

### Backup Configuration

```bash
# RDS automated backups are enabled
# For manual backup:
aws rds create-db-snapshot \
  --db-instance-identifier arquisoft-db \
  --db-snapshot-identifier arquisoft-db-backup-$(date +%Y%m%d)
```

---

## License

This project is for educational and production use within the Arquisoft program.

## Support

For issues or questions, please contact the project maintainers or check the [GitHub Issues](https://github.com/ARQUISOFT-202610/Sprint4/issues) page.
