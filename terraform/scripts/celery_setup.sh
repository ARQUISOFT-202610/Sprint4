#!/bin/bash
# Celery Worker Setup Script - Runs as user_data on first boot
exec > /var/log/user-data.log 2>&1
set -uo pipefail

echo "=== Celery Worker Setup Started ==="
date
echo "User: $(whoami)"
echo "Working directory: $(pwd)"

# Update system packages
echo "=== Updating System Packages ==="
apt-get update && apt-get upgrade -y || echo "WARNING: apt-get update/upgrade had issues"

# Install dependencies
echo "=== Installing Dependencies ==="
apt-get install -y \
  python3.12 python3.12-venv python3-pip \
  git postgresql-client curl \
  build-essential libssl-dev libffi-dev python3-dev || {
  echo "ERROR: Failed to install dependencies"
  exit 1
}

echo "Python version:"
python3.12 --version
echo "Git version:"
git --version

# Create app directory and log directories
echo "=== Creating directories ==="
mkdir -p /app /var/log/celery /var/run/celery
chmod 755 /app /var/log/celery /var/run/celery

echo "=== Cloning Repository ==="
cd /tmp

# Git clone with retry logic
CLONE_ATTEMPTS=0
MAX_CLONE_ATTEMPTS=3
until [ $CLONE_ATTEMPTS -eq $MAX_CLONE_ATTEMPTS ]; do
  CLONE_ATTEMPTS=$((CLONE_ATTEMPTS + 1))
  echo "Git clone attempt $CLONE_ATTEMPTS/$MAX_CLONE_ATTEMPTS..."
  
  if git clone https://x-access-token:${github_token}@github.com/ARQUISOFT-202610/Sprint4.git /app 2>&1; then
    echo "Git clone successful!"
    break
  else
    echo "Git clone failed, attempt $CLONE_ATTEMPTS/$MAX_CLONE_ATTEMPTS"
    if [ $CLONE_ATTEMPTS -lt $MAX_CLONE_ATTEMPTS ]; then
      sleep 15
      rm -rf /app 2>/dev/null || true
    fi
  fi
done

if [ $CLONE_ATTEMPTS -eq $MAX_CLONE_ATTEMPTS ]; then
  echo "ERROR: Git clone failed after $MAX_CLONE_ATTEMPTS attempts"
  exit 1
fi

cd /app
echo "Current directory: $(pwd)"
echo "Directory contents:"
ls -la /app

# Configure git
git remote set-url origin https://github.com/ARQUISOFT-202610/Sprint4.git || true

# Fix permissions
chmod -R 755 /app
chown -R ubuntu:ubuntu /app

echo "=== Creating Virtual Environment ==="
if [ -d "/app/venv" ]; then
  echo "Virtual environment already exists, removing it..."
  rm -rf /app/venv
fi

python3.12 -m venv /app/venv || {
  echo "ERROR: Failed to create virtual environment"
  exit 1
}

echo "=== Upgrading pip, setuptools, and wheel ==="
/app/venv/bin/pip install --upgrade pip setuptools wheel || {
  echo "ERROR: Failed to upgrade pip"
  exit 1
}

echo "=== Installing Python Dependencies ==="
if [ -f "/app/backend/requirements.txt" ]; then
  /app/venv/bin/pip install -r /app/backend/requirements.txt || {
    echo "ERROR: Failed to install Python dependencies"
    exit 1
  }
else
  echo "ERROR: requirements.txt not found at /app/backend/requirements.txt"
  ls -la /app/backend/ || true
  exit 1
fi

echo "=== Setting Environment Variables ==="
cat > /app/backend/.env << 'ENVEOF'
${env_file}
ENVEOF

chmod 600 /app/backend/.env
chown ubuntu:ubuntu /app/backend/.env
echo "Environment file created and permissions set"

# Source variables to use in the script
set +u  # Disable error on undefined variables temporarily
source /app/backend/.env || {
  echo "ERROR: Failed to source .env file"
  exit 1
}
set -u

echo "=== Waiting for RDS Database ==="
RDS_READY=false
RDS_TIMEOUT=0
MAX_RDS_TIMEOUT=300  # 5 minutes

while [ $RDS_TIMEOUT -lt $MAX_RDS_TIMEOUT ]; do
  if command -v psql &> /dev/null; then
    # Use variables from .env file
    if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" 2>/dev/null | grep -q "1"; then
      echo "RDS is ready!"
      RDS_READY=true
      break
    fi
  fi
  
  RDS_TIMEOUT=$((RDS_TIMEOUT + 10))
  echo "RDS check attempt $((RDS_TIMEOUT/10))/30 - waiting..."
  sleep 10
done

if [ "$RDS_READY" = false ]; then
  echo "WARNING: RDS did not become ready after 5 minutes, continuing anyway..."
fi

echo "=== Setting up Celery Logs and Directories ==="
mkdir -p /var/log/celery /var/run/celery
touch /var/log/celery/worker.log /var/log/celery/flower.log
chown -R ubuntu:ubuntu /var/log/celery /var/run/celery
chmod 755 /var/log/celery /var/run/celery

echo "=== Creating Celery Worker Systemd Service ==="
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
StandardOutput=append:/var/log/celery/worker.log
StandardError=append:/var/log/celery/worker.log
ExecStart=/app/venv/bin/celery -A config worker \
  --loglevel=info \
  --concurrency=4 \
  --time-limit=3600 \
  --soft-time-limit=3600

Restart=on-failure
RestartSec=10
StartLimitInterval=60s
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
SVCEOF

echo "=== Creating Flower (Celery Monitoring) Systemd Service ==="
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
StandardOutput=append:/var/log/celery/flower.log
StandardError=append:/var/log/celery/flower.log
ExecStart=/app/venv/bin/celery -A config flower \
  --port=5555

Restart=on-failure
RestartSec=10
StartLimitInterval=60s
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
SVCEOF

echo "=== Starting Celery Services ==="
systemctl daemon-reload

echo "Enabling and starting celery..."
systemctl enable celery || echo "WARNING: Failed to enable celery"
systemctl start celery || {
  echo "ERROR: Failed to start celery"
  journalctl -u celery -n 50 --no-pager || true
  exit 1
}

echo "Enabling and starting flower..."
systemctl enable flower || echo "WARNING: Failed to enable flower"
systemctl start flower || {
  echo "ERROR: Failed to start flower"
  journalctl -u flower -n 50 --no-pager || true
  exit 1
}

echo "=== Verifying Deployment ==="
sleep 5

echo "Celery service status:"
systemctl status celery --no-pager || true

echo "Flower service status:"
systemctl status flower --no-pager || true

echo "Listening ports:"
ss -tulpn | grep 5555 || echo "WARNING: Port 5555 not listening yet"

echo "Recent celery logs:"
journalctl -u celery -n 50 --no-pager || true

echo "Recent flower logs:"
journalctl -u flower -n 50 --no-pager || true

echo "=== Celery Setup Completed Successfully ==="
date
