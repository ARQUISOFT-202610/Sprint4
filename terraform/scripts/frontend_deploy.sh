#!/bin/bash
# Frontend React Deployment Script - Runs as user_data on first boot
exec > /var/log/user-data.log 2>&1
set -euo pipefail

echo "=== Frontend Setup Started ==="
date
echo "User: $(whoami)"
echo "Working directory: $(pwd)"

# Update system packages
echo "=== Updating System Packages ==="
apt-get update && apt-get upgrade -y || echo "WARNING: apt-get update/upgrade had issues"

# Install dependencies
echo "=== Installing Dependencies ==="
apt-get install -y \
  curl git build-essential \
  nginx-light || {
  echo "ERROR: Failed to install dependencies"
  exit 1
}

echo "Git version:"
git --version
echo "Curl version:"
curl --version | head -1

echo "=== Cloning Repository ==="
mkdir -p /app
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
echo "Repository contents:"
ls -la /app

# Configure git
git remote set-url origin https://github.com/ARQUISOFT-202610/Sprint4.git || true

# Fix permissions
chmod -R 755 /app
chown -R ubuntu:ubuntu /app

echo "=== Installing Node.js and npm ==="

# Install Node.js 18+ (using NodeSource repository)
if ! curl -fsSL https://deb.nodesource.com/setup_18.x | bash - 2>&1; then
  echo "WARNING: Failed to add NodeSource repository"
fi

apt-get install -y nodejs || {
  echo "ERROR: Failed to install Node.js"
  exit 1
}

# Verify Node.js and npm installation
echo "Node.js version:"
node --version
echo "npm version:"
npm --version

echo "=== Installing npm Dependencies ==="

# Navigate to frontend directory (if it exists)
if [ -d "/app/frontend" ]; then
  cd /app/frontend
  FRONTEND_DIR="/app/frontend"
elif [ -f "/app/package.json" ]; then
  cd /app
  FRONTEND_DIR="/app"
else
  echo "ERROR: Frontend package.json not found in /app or /app/frontend"
  ls -la /app || true
  exit 1
fi

echo "Frontend directory: $FRONTEND_DIR"
echo "Directory contents:"
ls -la "$FRONTEND_DIR"

# Install npm packages
if [ ! -f "package.json" ]; then
  echo "ERROR: package.json not found in $(pwd)"
  exit 1
fi

npm ci || {
  echo "ERROR: npm ci failed"
  exit 1
}

echo "=== Building React Application ==="

# Build the React application for production
npm run build || {
  echo "ERROR: npm run build failed"
  exit 1
}

# Verify build directory exists
if [ ! -d "build" ]; then
  echo "ERROR: Build directory not found at $(pwd)/build"
  ls -la || true
  exit 1
fi

BUILD_DIR="$(pwd)/build"
echo "Build directory: $BUILD_DIR"
echo "Build contents:"
ls -la "$BUILD_DIR"

echo "=== Installing TLS Certificate ==="

# Create SSL directory
mkdir -p /etc/nginx/ssl
chmod 755 /etc/nginx/ssl

# Write certificate file
cat > /etc/nginx/ssl/arquisoft.crt << 'CERTEOF'
${tls_certificate_pem}
CERTEOF

# Write private key file
cat > /etc/nginx/ssl/arquisoft.key << 'KEYEOF'
${tls_private_key_pem}
KEYEOF

# Set correct permissions
chmod 600 /etc/nginx/ssl/arquisoft.key
chmod 644 /etc/nginx/ssl/arquisoft.crt

echo "TLS Certificate installed successfully"

echo "=== Configuring Nginx ==="

# Create Nginx configuration for serving React static files with HTTPS
# The configuration includes:
# 1. HTTP to HTTPS redirect
# 2. TLS termination with self-signed certificate
# 3. Static file caching
# 4. SPA routing (try_files for React Router)
# 5. API proxy to Django ALB backend
cat > /etc/nginx/sites-available/frontend << 'NGINXEOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    # Redirect all HTTP requests to HTTPS
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;

    server_name _;

    # TLS Configuration
    ssl_certificate     /etc/nginx/ssl/arquisoft.crt;
    ssl_certificate_key /etc/nginx/ssl/arquisoft.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers        HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # React static files (point to actual build directory)
    root BUILD_DIR_PLACEHOLDER;
    index index.html index.htm;

    # Serve static files with long expiration
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # SPA routing: serve index.html for all non-file requests
    location / {
        try_files $uri /index.html;
    }

    # API proxy: forward requests to Django ALB
    location /api/ {
        proxy_pass http://${django_alb_dns}/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Health check endpoint (no SSL required for health checks)
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # Deny access to sensitive files
    location ~ /\. {
        deny all;
    }
}
NGINXEOF

# Replace placeholder with actual build directory
sed -i "s|BUILD_DIR_PLACEHOLDER|$BUILD_DIR|g" /etc/nginx/sites-available/frontend

echo "Nginx configuration created with build directory: $BUILD_DIR"

# Enable the Nginx configuration
ln -sf /etc/nginx/sites-available/frontend /etc/nginx/sites-enabled/frontend
rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
echo "=== Testing Nginx Configuration ==="
if ! nginx -t 2>&1; then
  echo "ERROR: Nginx configuration test failed"
  exit 1
fi

echo "=== Starting Nginx Service ==="

# Enable and start Nginx
systemctl daemon-reload
systemctl enable nginx || echo "WARNING: Failed to enable nginx"
systemctl start nginx || {
  echo "ERROR: Failed to start nginx"
  journalctl -u nginx -n 50 --no-pager || true
  exit 1
}

echo "=== Verifying Deployment ==="
sleep 3

echo "Nginx service status:"
systemctl status nginx --no-pager || true

echo "Nginx listening ports:"
ss -tulpn | grep nginx || echo "WARNING: Nginx not listening"

echo "Health check attempt (HTTPS - accepting self-signed certs):"
for i in {1..5}; do
  if curl -s -k https://localhost/health 2>/dev/null | grep -q healthy; then
    echo "Health check successful!"
    break
  else
    echo "Health check attempt $i/5 failed, waiting..."
    sleep 2
  fi
done

echo "Recent nginx logs:"
journalctl -u nginx -n 20 --no-pager || true

echo "=== Frontend Setup Completed Successfully ==="
date
echo "Frontend is now serving React application:"
echo "  HTTP  (redirects to HTTPS): http://localhost"
echo "  HTTPS (main endpoint):      https://localhost"
echo "  Build directory:            $BUILD_DIR"
echo "  API proxy:                  /api/ -> ${django_alb_dns}"
