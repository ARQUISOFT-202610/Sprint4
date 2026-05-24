#!/bin/bash
# FastAPI EC2 Setup Script - Runs as user_data on first boot
exec > /var/log/user-data.log 2>&1
set -euo pipefail

echo "=== FastAPI EC2 Setup Started ==="
date

# Update system packages
apt-get update && apt-get upgrade -y

# Install dependencies
apt-get install -y \
  python3.12 python3.12-venv python3-pip \
  git curl \
  build-essential libssl-dev libffi-dev python3-dev

echo "=== Installing CloudWatch Logs Agent ==="

wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i -E ./amazon-cloudwatch-agent.deb

mkdir -p /opt/aws/amazon-cloudwatch-agent/etc/
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json << 'CWCONFIGEOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "/arquisoft/fastapi",
            "log_stream_name": "{instance_id}-setup",
            "retention_in_days": 90
          },
          {
            "file_path": "/var/log/uvicorn/access.log",
            "log_group_name": "/arquisoft/fastapi",
            "log_stream_name": "{instance_id}-access",
            "retention_in_days": 90
          },
          {
            "file_path": "/var/log/uvicorn/error.log",
            "log_group_name": "/arquisoft/fastapi",
            "log_stream_name": "{instance_id}-error",
            "retention_in_days": 90
          }
        ]
      }
    }
  }
}
CWCONFIGEOF

echo "=== Starting CloudWatch Logs Agent Early ==="
mkdir -p /var/log/uvicorn
touch /var/log/user-data.log /var/log/uvicorn/access.log /var/log/uvicorn/error.log
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json \
  -s

echo "=== Cloning Repository ==="

cd /home/ubuntu
git clone https://x-access-token:${github_token}@github.com/ARQUISOFT-202610/Sprint4.git /app
cd /app
git remote set-url origin https://github.com/ARQUISOFT-202610/Sprint4.git
chown -R ubuntu:ubuntu /app

echo "=== Creating Virtual Environment ==="

python3.12 -m venv venv
# Usar rutas absolutas
/app/venv/bin/pip install --upgrade pip setuptools wheel

echo "=== Installing Python Dependencies ==="

/app/venv/bin/pip install -r backend/requirements.txt

echo "=== Setting Environment Variables ==="

cat > /app/backend/.env << 'ENVEOF'
${env_file}
ENVEOF

chown ubuntu:ubuntu /app/backend/.env

# Source variables to use in the script
set -a
source /app/backend/.env
set +a

echo "=== Setting up Uvicorn Logs ==="
mkdir -p /var/log/uvicorn
touch /var/log/uvicorn/access.log /var/log/uvicorn/error.log
chown -R ubuntu:ubuntu /var/log/uvicorn

echo "=== Starting Uvicorn (FastAPI) ==="

cat > /etc/systemd/system/fastapi.service << 'SVCEOF'
[Unit]
Description=Uvicorn application server for FastAPI
After=network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/app/backend
EnvironmentFile=/app/backend/.env
Environment="PYTHONPATH=/app/backend"
ExecStart=/app/venv/bin/uvicorn \
  main:app \
  --host 0.0.0.0 \
  --port 8001 \
  --workers 4 \
  --access-log \
  --log-level info

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable fastapi
systemctl start fastapi

echo "=== Verifying Deployment ==="
sleep 5
systemctl status fastapi --no-pager || true
ss -tulpn | grep 8001 || true
curl -s -f http://localhost:8001/health/ || echo "Health check failed"
journalctl -u fastapi --no-pager | tail -n 20

echo "=== FastAPI Setup Completed ==="
date
