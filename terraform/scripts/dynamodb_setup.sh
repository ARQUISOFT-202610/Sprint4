#!/bin/bash
# DynamoDB Local Setup Script - Runs as user_data on first boot
exec > /var/log/user-data.log 2>&1
set -euo pipefail

echo "=== DynamoDB Local EC2 Setup Started ==="
date

# Update system packages
apt-get update && apt-get upgrade -y

# Install Java (required for DynamoDB Local)
apt-get install -y default-jre-headless curl

echo "=== CloudWatch Logs Disabled ==="
echo "DynamoDB Local instance does not send logs to CloudWatch"
mkdir -p /var/log/dynamodb

echo "=== Creating DynamoDB Local Directory ==="
mkdir -p /opt/dynamodb
cd /opt/dynamodb

echo "=== Downloading DynamoDB Local ==="
# Download latest version of DynamoDB Local
wget https://s3.us-west-2.amazonaws.com/dynamodb-local/dynamodb_local_latest.zip
unzip -q dynamodb_local_latest.zip
rm dynamodb_local_latest.zip

echo "=== Setting up DynamoDB Local Service ==="

cat > /etc/systemd/system/dynamodb.service << 'SVCEOF'
[Unit]
Description=DynamoDB Local Service
After=network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/dynamodb
ExecStart=/usr/bin/java \
  -Djava.library.path=/opt/dynamodb/DynamoDBLocal_lib \
  -jar /opt/dynamodb/DynamoDBLocal.jar \
  -sharedDb \
  -inMemory \
  -port 8000

Restart=on-failure
RestartSec=10
StandardOutput=append:/var/log/dynamodb/dynamodb.log
StandardError=append:/var/log/dynamodb/dynamodb.log

[Install]
WantedBy=multi-user.target
SVCEOF

echo "=== Setting Permissions ==="
chown -R ubuntu:ubuntu /opt/dynamodb /var/log/dynamodb

echo "=== Starting DynamoDB Local Service ==="
systemctl daemon-reload
systemctl enable dynamodb
systemctl start dynamodb

echo "=== Verifying DynamoDB Local ==="
sleep 10

# Check if service is running
if systemctl is-active --quiet dynamodb; then
  echo "DynamoDB Local service is active"
else
  echo "WARNING: DynamoDB Local service failed to start"
  systemctl status dynamodb --no-pager || true
  journalctl -u dynamodb --no-pager | tail -n 30
fi

# Try to connect to DynamoDB Local
for i in {1..30}; do
  if curl -s http://localhost:8000/ > /dev/null 2>&1; then
    echo "DynamoDB Local is responding on port 8000!"
    break
  else
    echo "Attempt $i/30 - DynamoDB Local not responding yet..."
    sleep 2
  fi
done

ss -tulpn | grep 8000 || true
journalctl -u dynamodb --no-pager | tail -n 20

echo "=== DynamoDB Local Setup Completed ==="
date
