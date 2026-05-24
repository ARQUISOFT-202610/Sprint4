# IAM Configuration Documentation

## Overview

This Terraform configuration uses **AWS Academy's existing IAM roles** to comply with account restrictions. No new IAM roles or policies are created.

## IAM Instance Profile Used

**Instance Profile Name:** `LabInstanceProfile`  
**Role Name:** `LabRole`  
**Instance Profile ARN:** `arn:aws:iam::038039760594:instance-profile/LabInstanceProfile`

## Where IAM is Used

The IAM instance profile is configured in **all EC2 instances** throughout the infrastructure:

### 1. Django EC2 Instances
**Module:** `terraform/modules/ec2_django/`  
**File:** `main.tf` (line ~62)  
**Usage:** Launch Template `iam_instance_profile`

```terraform
iam_instance_profile {
  name = var.iam_instance_profile  # "LabInstanceProfile"
}
```

**Module Configuration in main.tf:**
```terraform
module "ec2_django" {
  ...
  iam_instance_profile = "LabInstanceProfile"
  ...
}
```

### 2. Celery Worker EC2 Instances
**Module:** `terraform/modules/ec2_celery/`  
**File:** `main.tf` (line ~57)  
**Usage:** Launch Template `iam_instance_profile`

```terraform
iam_instance_profile {
  name = var.iam_instance_profile  # "LabInstanceProfile"
}
```

**Module Configuration in main.tf:**
```terraform
module "ec2_celery" {
  ...
  iam_instance_profile = "LabInstanceProfile"
  ...
}
```

### 3. FastAPI EC2 Instances (NEW)
**Module:** `terraform/modules/ec2_fastapi/`  
**File:** `main.tf` (line ~62)  
**Usage:** Launch Template `iam_instance_profile`

```terraform
iam_instance_profile {
  name = var.iam_instance_profile  # "LabInstanceProfile"
}
```

**Module Configuration in main.tf:**
```terraform
module "ec2_fastapi" {
  ...
  iam_instance_profile = "LabInstanceProfile"
  ...
}
```

### 4. DynamoDB Local EC2 Instance (NEW)
**Module:** `terraform/modules/ec2_dynamodb/`  
**File:** `main.tf` (line ~53)  
**Usage:** EC2 Instance `iam_instance_profile`

```terraform
iam_instance_profile = var.iam_instance_profile  # "LabInstanceProfile"
```

**Module Configuration in main.tf:**
```terraform
module "ec2_dynamodb" {
  ...
  iam_instance_profile = "LabInstanceProfile"
  ...
}
```

### 5. Frontend EC2 Instances
**Module:** `terraform/modules/ec2_frontend/`  
**File:** `main.tf` (line ~54)  
**Usage:** Launch Template `iam_instance_profile`

```terraform
iam_instance_profile {
  name = var.iam_instance_profile  # "LabInstanceProfile"
}
```

**Module Configuration in main.tf:**
```terraform
module "ec2_frontend" {
  ...
  iam_instance_profile = "LabInstanceProfile"
  ...
}
```

## AWS Academy Compliance

### What LabInstanceProfile Provides

The `LabInstanceProfile` attached to `LabRole` provides the necessary permissions for:

✅ **CloudWatch Logs**
- Creating log groups and streams
- Writing logs from EC2 instances (Django, Celery, FastAPI only)
- Query logs in CloudWatch

**⚠️ Important:** DynamoDB Local instance does NOT use CloudWatch - logs are local only

✅ **EC2**
- Describing instances
- Managing instance metadata

✅ **SSM (Systems Manager)** (if needed for Session Manager)
- Starting sessions on instances

✅ **S3** (basic access)
- Reading from S3 buckets (for downloads like DynamoDB Local)

✅ **SQS**
- Reading/writing to SQS queues

✅ **RDS** (implicit via VPC)
- No additional permissions needed (TCP port access via security groups)

### What is NOT Created

❌ **No new IAM roles** - Uses existing `LabRole`  
❌ **No new IAM policies** - Uses existing managed policies  
❌ **No custom IAM resources** - Fully AWS Academy compliant

## How to Verify IAM Configuration

### Check Instance Profile in AWS Console

1. Go to **EC2** → **Instances**
2. Select any running instance
3. Go to **Details** tab
4. Look for **IAM instance profile** field
5. Should show: `LabInstanceProfile`

### Check Instance Role Permissions

1. Go to **IAM** → **Roles**
2. Search for: `LabRole`
3. Check **Permissions** tab
4. Should have policies for CloudWatch, EC2, SQS, etc.

### Test from Instance (via SSH)

```bash
# SSH into any EC2 instance
ssh -i ~/.ssh/arquisoft-key.pem ubuntu@<instance-public-ip>

# Check instance metadata
curl http://169.254.169.254/latest/meta-data/iam/info

# Test CloudWatch Logs access
aws logs describe-log-groups --region us-east-1

# Test SQS access
aws sqs list-queues --region us-east-1
```

## Variables & Defaults

### EC2 Modules Variables

All EC2 modules accept `iam_instance_profile` variable:

```terraform
variable "iam_instance_profile" {
  description = "IAM instance profile for EC2 instances"
  type        = string
  default     = null
}
```

### Main Configuration

In `terraform/main.tf`, all modules receive:

```terraform
iam_instance_profile = "LabInstanceProfile"
```

## Troubleshooting

### CloudWatch Logs Not Appearing

**Possible causes:**
1. CloudWatch agent not started
2. IAM role missing CloudWatch permissions
3. Log group doesn't exist

**Solution:**
```bash
# SSH into instance
ssh -i ~/.ssh/arquisoft-key.pem ubuntu@<instance-ip>

# Check CloudWatch agent status
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a query -m ec2

# Check agent logs
tail -100 /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log

# Verify IAM permissions
aws logs describe-log-groups --region us-east-1
```

### SQS Messages Not Processed

**Possible causes:**
1. IAM role missing SQS permissions
2. Celery not configured correctly
3. Queue name mismatch

**Solution:**
```bash
# Verify SQS access
aws sqs list-queues --region us-east-1
aws sqs send-message --queue-url <queue-url> --message-body "test"
```

## Security Considerations

✅ **Least Privilege**: LabRole uses AWS managed policies (minimal required)  
✅ **No Hard-coded Credentials**: Uses instance metadata for temporary credentials  
✅ **Automatic Rotation**: AWS rotates temporary credentials automatically  
✅ **No Secrets in Code**: All credentials obtained via instance profile  
✅ **Audit Trail**: All API calls logged to CloudTrail (AWS Academy feature)

## References

- **AWS IAM Roles for EC2**: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html
- **CloudWatch Agent with IAM**: https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/permissions-reference-cwl.html
- **AWS Academy Lab Roles**: Documented in AWS Academy environment setup
- **Instance Profiles**: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role_ec2_instance-profiles.html

## Summary

- ✅ Using existing AWS Academy `LabInstanceProfile`
- ✅ No new IAM resources created (AWS Academy compliant)
- ✅ All EC2 instances have proper instance profile attached
- ✅ CloudWatch, EC2, SQS permissions available
- ✅ No hard-coded credentials in code
- ✅ Temporary credentials via instance metadata

Everything is properly configured and ready for deployment! 🚀
