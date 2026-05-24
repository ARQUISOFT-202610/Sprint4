# FastAPI & DynamoDB Local - Quick Reference

**Deployment Status:** ✅ COMPLETE  
**Last Updated:** May 2026

---

## 🎯 What Was Deployed

### FastAPI Microservice
- **Type:** Auto Scaling Group (ASG)
- **Instances:** 1-3 (min: 1, max: 3, desired: 1)
- **Port:** 8001
- **AZs:** us-east-1a, us-east-1b (Multi-AZ redundancy ✅)
- **Status:** Running behind ALB with path-based routing

### DynamoDB Local
- **Type:** Single EC2 Instance (stateful)
- **Instance Type:** t2.micro
- **Port:** 8000 (In-memory, shared DB)
- **Status:** Running, communicates with FastAPI only

---

## 🚀 Access Points

### From ALB

```bash
# FastAPI endpoint (via path-based routing)
curl http://<ALB-DNS>/fastapi/health

# Django endpoint (default, unchanged)
curl http://<ALB-DNS>/api/
```

### Direct SSH Access

```bash
# Get instance IPs
FASTAPI_IP=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names arquisoft-fastapi-asg \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text | xargs -I {} aws ec2 describe-instances \
  --instance-ids {} --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

DYNAMODB_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=arquisoft-dynamodb-local" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

# SSH (replace with actual key path)
ssh -i ~/.ssh/arquisoft-key.pem ubuntu@$FASTAPI_IP
ssh -i ~/.ssh/arquisoft-key.pem ubuntu@$DYNAMODB_IP
```

---

## ✅ Redundancy Confirmation

**FastAPI Multi-AZ:** ✅ YES
- Minimum 1 instance across us-east-1a and us-east-1b
- Auto Scaling Group spans both availability zones
- Instances automatically replaced if unhealthy

**Configuration in Terraform:**
```terraform
vpc_zone_identifier = var.public_subnets  # Both us-east-1a and us-east-1b
```

---

## 📊 ALB Routing Rules

| Path Pattern | Target | Port | Status |
|-------------|--------|------|--------|
| `/fastapi/*` | FastAPI ASG | 8001 | ✅ Active (Priority 1) |
| `/` (default) | Django ASG | 8000 | ✅ Active (Default) |

**Implementation:** AWS ALB Listener Rules with path-based condition

---

## 🧪 Quick Verification Tests

### 1. FastAPI Health Check (2 minutes)
```bash
curl -i http://<ALB-DNS>/fastapi/health
# Expected: HTTP 200 OK
```

### 2. DynamoDB Connectivity (SSH only)
```bash
ssh -i ~/.ssh/arquisoft-key.pem ubuntu@<DYNAMODB-IP>
curl http://localhost:8000/
```

### 3. Target Group Health (AWS CLI)
```bash
aws elbv2 describe-target-health \
  --target-group-arn <fastapi-tg-arn> \
  --region us-east-1
```

### 4. CloudWatch Logs (FastAPI only)
```bash
aws logs tail /arquisoft/fastapi --follow --region us-east-1
# Note: DynamoDB logs are local only (/var/log/dynamodb/dynamodb.log)
```

---

## 📋 Key Files

| File | Purpose |
|------|---------|
| `terraform/modules/ec2_fastapi/` | FastAPI ASG configuration |
| `terraform/modules/ec2_dynamodb/` | DynamoDB Local instance |
| `terraform/scripts/fastapi_setup.sh` | FastAPI initialization script |
| `terraform/scripts/dynamodb_setup.sh` | DynamoDB Local initialization script |
| `terraform/modules/alb/main.tf` | ALB with path-based routing rules |
| `TESTING_FASTAPI_DYNAMODB.md` | **Complete testing procedures** |
| `IAM_CONFIGURATION.md` | IAM instance profile usage |

---

## 🔒 Security Configuration

### FastAPI Security Group
- ✅ Ingress: 8001 from ALB
- ✅ Ingress: 22 from 0.0.0.0/0 (SSH)
- ✅ Egress: All traffic (for external APIs)

### DynamoDB Security Group
- ✅ Ingress: 8000 from FastAPI SG only
- ✅ Ingress: 22 from 0.0.0.0/0 (SSH)
- ✅ Egress: All traffic

### ALB Security Group
- ✅ Ingress: 80 from 0.0.0.0/0 (HTTP)
- ✅ Ingress: 443 from 0.0.0.0/0 (HTTPS)

---

## 📈 Monitoring

### CloudWatch Logs Available For

| Service | Log Group | Status |
|---------|-----------|--------|
| FastAPI | `/arquisoft/fastapi` | ✅ Sending logs (90-day retention) |
| Django | `/arquisoft/django` | ✅ Existing |
| Celery | `/arquisoft/celery` | ✅ Existing |
| **DynamoDB** | **Local only** | ⚠️ Not sent to CloudWatch |

**Access Logs:**
```bash
# FastAPI
aws logs tail /arquisoft/fastapi --follow

# DynamoDB (SSH to instance)
ssh -i ~/.ssh/arquisoft-key.pem ubuntu@<DYNAMODB-IP>
tail -f /var/log/dynamodb/dynamodb.log
```

---

## 🛠️ Common Operations

### Scale FastAPI
```bash
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name arquisoft-fastapi-asg \
  --desired-capacity 2 \
  --region us-east-1
```

### Check FastAPI Service Status (via SSH)
```bash
ssh -i ~/.ssh/arquisoft-key.pem ubuntu@<FASTAPI-IP>
systemctl status fastapi
journalctl -u fastapi -n 50
```

### Check DynamoDB Service Status (via SSH)
```bash
ssh -i ~/.ssh/arquisoft-key.pem ubuntu@<DYNAMODB-IP>
systemctl status dynamodb
sudo ss -tulpn | grep 8000
```

### Create Test Table in DynamoDB
```bash
ssh -i ~/.ssh/arquisoft-key.pem ubuntu@<DYNAMODB-IP>

aws dynamodb create-table \
  --table-name my-table \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --endpoint-url http://localhost:8000 \
  --region us-east-1
```

---

## ⚠️ Known Limitations

1. **DynamoDB is In-Memory Only**
   - Data is lost when instance stops
   - Not suitable for persistent storage
   - Use for development/testing only

2. **DynamoDB Not Connected to CloudWatch**
   - By design (AWS Academy restriction)
   - Logs are local: `/var/log/dynamodb/dynamodb.log`
   - SSH access required to view logs

3. **Single DynamoDB Instance**
   - No failover if instance fails
   - Data loss on instance termination
   - Stateful service (not in ASG)

---

## 📚 For More Details

- **Full Testing Guide:** `TESTING_FASTAPI_DYNAMODB.md`
- **Deployment Summary:** `DEPLOYMENT_SUMMARY.md`
- **IAM Configuration:** `IAM_CONFIGURATION.md`
- **Manual Steps:** `MANUAL_STEPS.md`

---

## 📞 Troubleshooting

**FastAPI not responding?**
→ See `TESTING_FASTAPI_DYNAMODB.md` → Troubleshooting → FastAPI Health Check Failing

**DynamoDB connection issues?**
→ See `TESTING_FASTAPI_DYNAMODB.md` → Troubleshooting → DynamoDB Connection Issues

**Path-based routing not working?**
→ See `TESTING_FASTAPI_DYNAMODB.md` → Troubleshooting → Path-Based Routing Not Working

---

**Status:** ✅ All systems deployed and operational  
**Next Steps:** Run comprehensive tests using `TESTING_FASTAPI_DYNAMODB.md`
