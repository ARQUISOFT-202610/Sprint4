#!/bin/bash
# Django EC2 Setup Script - Runs as user_data on first boot
exec > /var/log/user-data.log 2>&1
# NOTE: No usamos set -euo pipefail para que el script no muera en el primer error
# En su lugar cada paso critico tiene su propio manejo de errores
set -uo pipefail

echo "=== Django EC2 Setup Started ==="
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

# Create app directory and log directory
echo "=== Creating directories ==="
mkdir -p /app /var/log/gunicorn
chmod 755 /app /var/log/gunicorn

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
    # Use variables from .env file (already sourced above)
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

echo "=== Running Django Migrations ==="
# Reintentar migraciones hasta 3 veces (RDS puede tardar en aceptar conexiones)
MIGRATION_ATTEMPTS=0
until [ $MIGRATION_ATTEMPTS -ge 3 ]; do
  MIGRATION_ATTEMPTS=$((MIGRATION_ATTEMPTS + 1))
  echo "Migration attempt $MIGRATION_ATTEMPTS/3..."
  if /app/venv/bin/python /app/backend/manage.py migrate --run-syncdb --noinput 2>&1; then
    echo "Migrations successful!"
    break
  else
    echo "Migration failed, waiting 15s before retry..."
    sleep 15
  fi
done

echo "=== Collecting Static Files ==="
/app/venv/bin/python /app/backend/manage.py collectstatic --noinput || {
  echo "ERROR: Collecting static files failed"
  exit 1
}

echo "=== Setting up Gunicorn Logs ==="
mkdir -p /var/log/gunicorn
touch /var/log/gunicorn/access.log /var/log/gunicorn/error.log
chown -R ubuntu:ubuntu /var/log/gunicorn
chmod 755 /var/log/gunicorn

echo "=== Creating Gunicorn Systemd Service ==="
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
StandardOutput=append:/var/log/gunicorn/access.log
StandardError=append:/var/log/gunicorn/error.log
ExecStart=/app/venv/bin/gunicorn \
  --bind 0.0.0.0:8000 \
  --workers 4 \
  --worker-class gevent \
  --worker-connections 1000 \
  --timeout 120 \
  --keep-alive 5 \
  --access-logfile - \
  --error-logfile - \
  --capture-output \
  --enable-stdio-inheritance \
  config.wsgi:application

Restart=on-failure
RestartSec=5
StartLimitInterval=60s
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
SVCEOF

echo "=== Starting Gunicorn Service ==="
systemctl daemon-reload
systemctl enable gunicorn || echo "WARNING: Failed to enable gunicorn"
systemctl start gunicorn || {
  echo "ERROR: Failed to start gunicorn"
  journalctl -u gunicorn -n 50 --no-pager || true
  exit 1
}

echo "=== Verifying Deployment ==="
sleep 5

echo "Gunicorn service status:"
systemctl status gunicorn --no-pager || true

echo "Listening ports:"
ss -tulpn | grep 8000 || echo "WARNING: Port 8000 not listening yet"

echo "Health check attempt:"
for i in {1..5}; do
  if curl -s -f http://localhost:8000/health/ 2>/dev/null; then
    echo "Health check successful!"
    break
  else
    echo "Health check attempt $i/5 failed, waiting..."
    sleep 2
  fi
done

echo "Recent gunicorn logs:"
journalctl -u gunicorn -n 50 --no-pager || true

echo "=== Django Setup Completed Successfully ==="
date
