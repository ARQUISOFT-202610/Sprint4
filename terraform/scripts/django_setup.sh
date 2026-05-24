#!/bin/bash
# Django EC2 Setup Script - Runs as user_data on first boot
exec > /var/log/user-data.log 2>&1
set -euo pipefail

echo "=== Django EC2 Setup Started ==="
date

# Update system packages
apt-get update && apt-get upgrade -y

# Install dependencies
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
            "log_group_name": "/arquisoft/django",
            "log_stream_name": "{instance_id}-setup",
            "retention_in_days": 90
          },
          {
            "file_path": "/var/log/gunicorn/access.log",
            "log_group_name": "/arquisoft/django",
            "log_stream_name": "{instance_id}-access",
            "retention_in_days": 90
          },
          {
            "file_path": "/var/log/gunicorn/error.log",
            "log_group_name": "/arquisoft/django",
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
mkdir -p /var/log/gunicorn
touch /var/log/user-data.log /var/log/gunicorn/access.log /var/log/gunicorn/error.log
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json \
  -s

echo "=== Cloning Repository ==="

cd /home/ubuntu
git clone https://x-access-token:${github_token}@github.com/ARQUISOFT-202610/Sprint3.git /app
cd /app
git remote set-url origin https://github.com/ARQUISOFT-202610/Sprint3.git
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

echo "=== Waiting for RDS ==="

RDS_READY=false
for i in {1..30}; do
  if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" 2>/dev/null; then
    echo "RDS is ready!"
    RDS_READY=true
    break
  else
    echo "RDS attempt $i/30 - waiting..."
    sleep 10
  fi
done

if [ "$RDS_READY" = false ]; then
  echo "ERROR: RDS did not become ready after 5 minutes — aborting"
  exit 1
fi

echo "=== Running Django Migrations ==="

/app/venv/bin/python /app/backend/manage.py migrate --noinput

echo "=== Collecting Static Files ==="

/app/venv/bin/python /app/backend/manage.py collectstatic --noinput

echo "=== Setting up Gunicorn Logs ==="
mkdir -p /var/log/gunicorn
touch /var/log/gunicorn/access.log /var/log/gunicorn/error.log
chown -R ubuntu:ubuntu /var/log/gunicorn

echo "=== Starting Gunicorn ==="

cat > /etc/systemd/system/gunicorn.service << 'SVCEOF'
[Unit]
Description=Gunicorn application server for Django
After=network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/app/backend
EnvironmentFile=/app/backend/.env
Environment="DJANGO_SETTINGS_MODULE=config.django_settings"
Environment="PYTHONPATH=/app/backend"
ExecStart=/app/venv/bin/gunicorn \
  --bind 0.0.0.0:8000 \
  --workers 4 \
  --worker-class sync \
  --access-logfile /var/log/gunicorn/access.log \
  --error-logfile /var/log/gunicorn/error.log \
  --capture-output \
  --enable-stdio-inheritance \
  config.wsgi:application

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable gunicorn
systemctl start gunicorn


echo "=== Verifying Deployment ==="
sleep 5
systemctl status gunicorn --no-pager || true
ss -tulpn | grep 8000 || true
curl -s -f http://localhost:8000/health/ || echo "Health check failed"
journalctl -u gunicorn --no-pager | tail -n 20

echo "=== Django Setup Completed ==="
date
