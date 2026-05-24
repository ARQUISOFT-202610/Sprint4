# FastAPI & DynamoDB Local - Testing Guide

**Purpose:** Comprehensive testing guide to verify FastAPI and DynamoDB Local instances are functioning correctly after deployment.

**Last Updated:** May 2026  
**Status:** Post-Deployment Testing

---

## 📋 Table of Contents

1. [Pre-Test Checklist](#pre-test-checklist)
2. [FastAPI Instance Tests](#fastapi-instance-tests)
3. [DynamoDB Local Tests](#dynamodb-local-tests)
4. [FastAPI ↔ DynamoDB Communication](#fastapi--dynamodb-communication)
5. [ALB Routing Tests](#alb-routing-tests)
6. [Multi-AZ Redundancy Verification](#multi-az-redundancy-verification)
7. [Troubleshooting](#troubleshooting)

---

## Pre-Test Checklist

### Get Deployment Information

```bash
# Get ALB DNS name
ALB_DNS=$(cd terraform && terraform output -raw alb_dns_name)
echo "ALB DNS: $ALB_DNS"

# Get FastAPI ASG name
FASTAPI_ASG=$(cd terraform && terraform output -raw fastapi_asg_name)
echo "FastAPI ASG: $FASTAPI_ASG"

# Get DynamoDB instance IP
DYNAMODB_IP=$(cd terraform && terraform output -raw dynamodb_private_ip)
echo "DynamoDB Private IP: $DYNAMODB_IP"

# Get DynamoDB public IP for SSH
DYNAMODB_PUBLIC=$(cd terraform && terraform output -raw dynamodb_public_ip)
echo "DynamoDB Public IP: $DYNAMODB_PUBLIC"

# Get EC2 Key Pair path
KEY_PATH=$(cd terraform && terraform output -raw ec2_private_key_path)
echo "Key Path: $KEY_PATH"
```

---

## FastAPI Instance Tests

### 1. Verify FastAPI Instances Are Running

```bash
# List FastAPI instances in ASG
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$FASTAPI_ASG" \
  --region us-east-1 \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,AvailabilityZone,HealthStatus]' \
  --output table
```

**Expected Output:**
- 1-3 instances running
- Instances in both `us-east-1a` and `us-east-1b` (multi-AZ)
- HealthStatus: `Healthy`

### 2. Check FastAPI Application Health Endpoint

```bash
# Test via ALB with path-based routing
curl -v "http://$ALB_DNS/fastapi/health"

# Expected response:
# HTTP/1.1 200 OK
# {"status": "healthy"}
```

### 3. Direct SSH to FastAPI Instance

```bash
# Get a FastAPI instance ID
FASTAPI_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$FASTAPI_ASG" \
  --region us-east-1 \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text)

# Get public IP
FASTAPI_IP=$(aws ec2 describe-instances \
  --instance-ids "$FASTAPI_ID" \
  --region us-east-1 \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "FastAPI Instance IP: $FASTAPI_IP"

# SSH into instance
ssh -i "$KEY_PATH" ubuntu@"$FASTAPI_IP"
```

### 4. Verify FastAPI Service on Instance

Once SSH'd into FastAPI instance:

```bash
# Check if FastAPI service is running
systemctl status fastapi

# Check if port 8001 is listening
sudo ss -tulpn | grep 8001

# View recent logs
journalctl -u fastapi -n 50 --no-pager

# Test locally
curl http://localhost:8001/health
curl http://localhost:8001/fastapi/health
```

### 5. Check CloudWatch Logs for FastAPI

```bash
# Tail FastAPI logs in CloudWatch
aws logs tail /arquisoft/fastapi --follow --region us-east-1

# Or get recent logs
aws logs describe-log-streams \
  --log-group-name /arquisoft/fastapi \
  --region us-east-1 \
  --order-by LastEventTime \
  --descending
```

---

## DynamoDB Local Tests

### 1. Verify DynamoDB Instance is Running

```bash
# Check instance status
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=arquisoft-dynamodb-local" \
  --region us-east-1 \
  --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]' \
  --output table

# Expected: running state, has public and private IPs
```

### 2. SSH to DynamoDB Instance

```bash
ssh -i "$KEY_PATH" ubuntu@"$DYNAMODB_PUBLIC"
```

### 3. Verify DynamoDB Local Service on Instance

Once SSH'd into DynamoDB instance:

```bash
# Check service status
systemctl status dynamodb

# Check if port 8000 is listening
sudo ss -tulpn | grep 8000

# View DynamoDB logs
tail -f /var/log/dynamodb/dynamodb.log

# Test DynamoDB Local locally
curl -s http://localhost:8000/ | jq '.'

# Expected: Empty response or DynamoDB Local API response
```

### 4. Test DynamoDB with AWS CLI from Instance

```bash
# On DynamoDB instance, create a test table
aws dynamodb create-table \
  --table-name test-table \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --endpoint-url http://localhost:8000 \
  --region us-east-1

# List tables (verify creation)
aws dynamodb list-tables \
  --endpoint-url http://localhost:8000 \
  --region us-east-1

# Put test item
aws dynamodb put-item \
  --table-name test-table \
  --item '{"id": {"S": "test-1"}, "name": {"S": "Test Item"}}' \
  --endpoint-url http://localhost:8000 \
  --region us-east-1

# Get test item
aws dynamodb get-item \
  --table-name test-table \
  --key '{"id": {"S": "test-1"}}' \
  --endpoint-url http://localhost:8000 \
  --region us-east-1

# Delete test table (cleanup)
aws dynamodb delete-table \
  --table-name test-table \
  --endpoint-url http://localhost:8000 \
  --region us-east-1
```

### 5. Check DynamoDB Logs Locally

```bash
# On DynamoDB instance - view logs
cat /var/log/dynamodb/dynamodb.log

# Or tail in real-time
sudo tail -f /var/log/dynamodb/dynamodb.log
```

---

## FastAPI ↔ DynamoDB Communication

### 1. Test from FastAPI Instance to DynamoDB

SSH into a FastAPI instance and test connectivity:

```bash
# Check if DynamoDB endpoint is accessible
curl -v http://$DYNAMODB_IP:8000/

# Expected: HTTP 200 or valid DynamoDB response

# Check DynamoDB endpoint in FastAPI .env
cat /opt/fastapi/.env | grep DYNAMODB_ENDPOINT

# Expected: http://<dynamodb-private-ip>:8000
```

### 2. Verify FastAPI Can Query DynamoDB

SSH into FastAPI instance:

```bash
# Check if boto3 / FastAPI can reach DynamoDB
python3 << 'EOF'
import os
import requests
from dotenv import load_dotenv

load_dotenv('/opt/fastapi/.env')
dynamodb_endpoint = os.getenv('DYNAMODB_ENDPOINT')

print(f"Testing DynamoDB Endpoint: {dynamodb_endpoint}")

try:
    response = requests.get(f"{dynamodb_endpoint}/")
    print(f"Status Code: {response.status_code}")
    print(f"Response: {response.text}")
except Exception as e:
    print(f"ERROR: {e}")
EOF
```

### 3. Check Security Group Rules

```bash
# Verify FastAPI → DynamoDB rule
aws ec2 describe-security-group-rules \
  --filters "Name=description,Values=Allow FastAPI to connect to DynamoDB Local" \
  --region us-east-1 \
  --query 'SecurityGroupRules[0].[GroupId,IsEgress,FromPort,ToPort,CidrIpv6,ReferencedGroupInfo.GroupId]' \
  --output table

# Expected: Rule exists, port 8000, source is FastAPI SG
```

---

## ALB Routing Tests

### 1. Test Default Route (Django)

```bash
# Access Django via ALB (default path)
curl -v "http://$ALB_DNS/health/"

# Expected: HTTP 200, Django health check response
```

### 2. Test Path-Based Routing to FastAPI

```bash
# Access FastAPI via ALB with /fastapi/ path
curl -v "http://$ALB_DNS/fastapi/health"

# Expected: HTTP 200, FastAPI health check response
```

### 3. Verify ALB Target Group Health

```bash
# Check Django target group
aws elbv2 describe-target-health \
  --target-group-arn $(cd terraform && terraform output -raw django_target_group_arn) \
  --region us-east-1 \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' \
  --output table

# Check FastAPI target group
aws elbv2 describe-target-health \
  --target-group-arn $(cd terraform && terraform output -raw fastapi_target_group_arn) \
  --region us-east-1 \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' \
  --output table

# Expected: All targets showing "healthy"
```

### 4. Test ALB Listener Rules

```bash
# Describe listener rules
aws elbv2 describe-rules \
  --listener-arn $(aws elbv2 describe-listeners \
    --load-balancer-arn $(cd terraform && terraform output -raw alb_arn) \
    --region us-east-1 \
    --query 'Listeners[0].ListenerArn' \
    --output text) \
  --region us-east-1 \
  --query 'Rules[*].[Priority,Conditions[0].Values[0],TargetGroupArn]' \
  --output table

# Expected:
# Priority | Path                | Target Group
# default  | -                   | Django TG (8000)
# 1        | /fastapi/*          | FastAPI TG (8001)
```

---

## Multi-AZ Redundancy Verification

### 1. Verify FastAPI Instances in Multiple AZs

```bash
# Check ASG instances and their AZs
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$FASTAPI_ASG" \
  --region us-east-1 \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,AvailabilityZone]' \
  --output table

# Expected output should show instances in:
# - us-east-1a (public subnet 1)
# - us-east-1b (public subnet 2)
```

### 2. Verify Network Configuration

```bash
# Check public subnets created in different AZs
aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=arquisoft-public-subnet-*" \
  --region us-east-1 \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# Expected:
# - public subnet 1: 10.0.1.0/24 in us-east-1a
# - public subnet 2: 10.0.3.0/24 in us-east-1b
```

### 3. Verify ALB Spans Multiple AZs

```bash
# Check ALB subnets
aws elbv2 describe-load-balancers \
  --load-balancer-arns $(cd terraform && terraform output -raw alb_arn) \
  --region us-east-1 \
  --query 'LoadBalancers[0].AvailabilityZones[*].[ZoneName,SubnetId]' \
  --output table

# Expected: ALB in both us-east-1a and us-east-1b
```

### 4. Simulate AZ Failure (Optional)

**Warning:** This will temporarily affect availability.

```bash
# Stop a FastAPI instance in one AZ
FASTAPI_ID_AZ_A=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$FASTAPI_ASG" \
  --region us-east-1 \
  --query 'AutoScalingGroups[0].Instances[?AvailabilityZone==`us-east-1a`].InstanceId' \
  --output text | head -1)

# Stop the instance
aws ec2 stop-instances --instance-ids "$FASTAPI_ID_AZ_A" --region us-east-1

# Wait 30 seconds, then test ALB
sleep 30
curl -v "http://$ALB_DNS/fastapi/health"

# Expected: Still works (ASG launches new instance in the AZ)

# Start the instance again
aws ec2 start-instances --instance-ids "$FASTAPI_ID_AZ_A" --region us-east-1
```

---

## Troubleshooting

### FastAPI Health Check Failing

**Symptoms:** `curl http://$ALB_DNS/fastapi/health` returns 502 or connection timeout

**Checks:**
```bash
# 1. Verify instances are running
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$FASTAPI_ASG" \
  --region us-east-1 \
  --query 'AutoScalingGroups[0].Instances' \
  --output json

# 2. Check target group health
aws elbv2 describe-target-health \
  --target-group-arn $(cd terraform && terraform output -raw fastapi_target_group_arn) \
  --region us-east-1

# 3. SSH to instance and check service
ssh -i "$KEY_PATH" ubuntu@"$FASTAPI_IP"
systemctl status fastapi
journalctl -u fastapi -n 30 --no-pager
```

### DynamoDB Connection Issues

**Symptoms:** FastAPI can't connect to DynamoDB, or DynamoDB health check fails

**Checks:**
```bash
# 1. Verify DynamoDB instance is running
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=arquisoft-dynamodb-local" \
  --region us-east-1 \
  --query 'Reservations[0].Instances[0].State.Name'

# 2. Check security group rules
aws ec2 describe-security-group-rules \
  --filters "Name=description,Values=Allow FastAPI to connect to DynamoDB Local" \
  --region us-east-1

# 3. SSH to DynamoDB instance
ssh -i "$KEY_PATH" ubuntu@"$DYNAMODB_PUBLIC"
systemctl status dynamodb
sudo ss -tulpn | grep 8000
```

### Path-Based Routing Not Working

**Symptoms:** `/fastapi/health` routes to Django instead of FastAPI

**Checks:**
```bash
# 1. Verify listener rules are configured
aws elbv2 describe-rules \
  --listener-arn $(aws elbv2 describe-listeners \
    --load-balancer-arn $(cd terraform && terraform output -raw alb_arn) \
    --region us-east-1 \
    --query 'Listeners[0].ListenerArn' \
    --output text) \
  --region us-east-1 \
  --output json | jq '.Rules[] | {Priority, Conditions, TargetGroupArn}'

# 2. Check if FastAPI target group was created
aws elbv2 describe-target-groups \
  --region us-east-1 \
  --query 'TargetGroups[?contains(TargetGroupName, `fastapi`)]'
```

### CloudWatch Logs Not Appearing

**For FastAPI:**
```bash
# Check if log group exists
aws logs describe-log-groups \
  --log-group-name-prefix /arquisoft/fastapi \
  --region us-east-1

# Check log streams
aws logs describe-log-streams \
  --log-group-name /arquisoft/fastapi \
  --region us-east-1
```

**For DynamoDB:**
DynamoDB Local logs are local only. SSH to instance and check:
```bash
ssh -i "$KEY_PATH" ubuntu@"$DYNAMODB_PUBLIC"
cat /var/log/dynamodb/dynamodb.log
tail -f /var/log/dynamodb/dynamodb.log
```

---

## Test Summary Checklist

- [ ] FastAPI instances are running (1-3 in ASG)
- [ ] FastAPI instances are in both us-east-1a and us-east-1b
- [ ] FastAPI health check responds via ALB (`/fastapi/health`)
- [ ] DynamoDB Local instance is running
- [ ] DynamoDB Local responds on port 8000
- [ ] FastAPI can connect to DynamoDB endpoint
- [ ] Security group rules allow FastAPI → DynamoDB
- [ ] ALB path-based routing works (`/fastapi/*` → FastAPI)
- [ ] Django still works via default route (`/` → Django)
- [ ] All target groups show healthy
- [ ] CloudWatch logs appear for FastAPI
- [ ] Multi-AZ redundancy is operational

---

## Performance Notes

- FastAPI instances should reach healthy state within 2-3 minutes of launch
- DynamoDB Local typically starts within 30 seconds
- Health checks run every 30 seconds (ALB default)
- Path-based routing is instant (no additional latency)

---

## Next Steps

After all tests pass:
1. Deploy application-specific integration tests
2. Load test FastAPI with Apache Bench or Locust
3. Monitor DynamoDB performance during load
4. Set up CloudWatch alarms for key metrics
5. Plan capacity based on load test results
