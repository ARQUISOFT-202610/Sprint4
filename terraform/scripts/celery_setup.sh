#!/bin/bash
# Celery Worker Setup Script - Runs as user_data on first boot
exec > /var/log/user-data.log 2>&1
set -euo pipefail

echo "=== Celery Worker Setup Started ==="
date

apt-get update && apt-get upgrade -y

apt-get install -y \
  python3.12 python3.12-venv python3-pip \
  git postgresql-client curl \
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
            "log_group_name": "/arquisoft/celery",
            "log_stream_name": "{instance_id}-setup",
            "retention_in_days": 90
          },
          {
            "file_path": "/var/log/celery/worker.log",
            "log_group_name": "/arquisoft/celery",
            "log_stream_name": "{instance_id}-worker",
            "retention_in_days": 90
          },
          {
            "file_path": "/var/log/celery/flower.log",
            "log_group_name": "/arquisoft/celery",
            "log_stream_name": "{instance_id}-flower",
            "retention_in_days": 90
          }
        ]
      }
    }
  }
}
CWCONFIGEOF

echo "=== Starting CloudWatch Logs Agent Early ==="
mkdir -p /var/log/celery /var/run/celery
touch /var/log/user-data.log /var/log/celery/worker.log /var/log/celery/flower.log
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
/app/venv/bin/pip install --upgrade pip setuptools wheel

echo "=== Installing Python Dependencies ==="

/app/venv/bin/pip install -r backend/requirements.txt

echo "=== Setting Environment Variables ==="

cat > /app/backend/.env << 'ENVEOF'
${env_file}
ENVEOF

chown ubuntu:ubuntu /app/backend/.env

set -a
source /app/backend/.env
set +a

echo "=== Waiting for Services ==="

RDS_READY=false
for i in {1..20}; do
  if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" 2>/dev/null; then
    echo "RDS is ready!"
    RDS_READY=true
    break
  else
    echo "RDS attempt $i/20 - waiting..."
    sleep 10
  fi
done

if [ "$RDS_READY" = false ]; then
  echo "ERROR: RDS did not become ready after 3 minutes — aborting"
  exit 1
fi

echo "=== Setting up Celery Logs and Dirs ==="
mkdir -p /var/log/celery /var/run/celery
touch /var/log/celery/worker.log /var/log/celery/flower.log
chown -R ubuntu:ubuntu /var/log/celery /var/run/celery

echo "=== Starting Celery Worker ==="

cat > /etc/systemd/system/celery.service << 'SVCEOF'
[Unit]
Description=Celery Service
After=network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/app/backend
EnvironmentFile=/app/backend/.env
Environment="DJANGO_SETTINGS_MODULE=config.django_settings"
Environment="PYTHONPATH=/app/backend"
ExecStart=/app/venv/bin/celery -A config worker \
  --loglevel=info \
  --logfile=/var/log/celery/worker.log \
  --concurrency=4 \
  --time-limit=3600 \
  --soft-time-limit=3600

Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable celery
systemctl start celery

echo "=== Starting Flower (Celery Monitoring) ==="

cat > /etc/systemd/system/flower.service << 'SVCEOF'
[Unit]
Description=Flower - Celery Monitoring
After=network.target celery.service

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/app/backend
EnvironmentFile=/app/backend/.env
Environment="DJANGO_SETTINGS_MODULE=config.django_settings"
Environment="PYTHONPATH=/app/backend"
ExecStart=/app/venv/bin/celery -A config flower \
  --port=5555 \
  --logfile=/var/log/celery/flower.log

Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl enable flower
systemctl start flower


echo "=== Verifying Deployment ==="
sleep 5
systemctl status celery --no-pager || true
systemctl status flower --no-pager || true
ss -tulpn | grep 5555 || true
journalctl -u celery --no-pager | tail -n 20

echo "=== Celery Setup Completed ==="
date
