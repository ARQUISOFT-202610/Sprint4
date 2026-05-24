#!/bin/bash
# FastAPI EC2 Setup Script - Runs as user_data on first boot
exec > /var/log/user-data.log 2>&1
set -euo pipefail

echo "=== FastAPI EC2 Setup Started ==="
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
  git curl \
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
mkdir -p /app /var/log/uvicorn
chmod 755 /app /var/log/uvicorn

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

echo "=== Setting up Uvicorn Logs ==="
mkdir -p /var/log/uvicorn
touch /var/log/uvicorn/access.log /var/log/uvicorn/error.log
chown -R ubuntu:ubuntu /var/log/uvicorn
chmod 755 /var/log/uvicorn

echo "=== Creating FastAPI Systemd Service ==="
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
StandardOutput=append:/var/log/uvicorn/access.log
StandardError=append:/var/log/uvicorn/error.log
ExecStart=/app/venv/bin/uvicorn \
  main:app \
  --host 0.0.0.0 \
  --port 8001 \
  --workers 4 \
  --access-log \
  --log-level info

Restart=on-failure
RestartSec=5
StartLimitInterval=60s
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
SVCEOF

echo "=== Starting FastAPI Service ==="
systemctl daemon-reload
systemctl enable fastapi || echo "WARNING: Failed to enable fastapi"
systemctl start fastapi || {
  echo "ERROR: Failed to start fastapi"
  journalctl -u fastapi -n 50 --no-pager || true
  exit 1
}

echo "=== Verifying Deployment ==="
sleep 5

echo "FastAPI service status:"
systemctl status fastapi --no-pager || true

echo "Listening ports:"
ss -tulpn | grep 8001 || echo "WARNING: Port 8001 not listening yet"

echo "Health check attempt:"
for i in {1..5}; do
  if curl -s -f http://localhost:8001/health/ 2>/dev/null; then
    echo "Health check successful!"
    break
  else
    echo "Health check attempt $i/5 failed, waiting..."
    sleep 2
  fi
done

echo "Recent fastapi logs:"
journalctl -u fastapi -n 50 --no-pager || true

echo "=== FastAPI Setup Completed Successfully ==="
date
