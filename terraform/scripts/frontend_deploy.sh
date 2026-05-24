#!/bin/bash
# Frontend React Deployment Script - Runs as user_data on first boot
exec > /var/log/user-data.log 2>&1
set -euo pipefail

echo "=== Frontend Setup Started ==="
date

# Update system packages
apt-get update && apt-get upgrade -y

# Install dependencies
apt-get install -y \
  curl git build-essential \
  nginx-light

# ============================================================================
# IMPORTANT: Install CloudWatch Logs Agent
# ============================================================================
# The CloudWatch Logs Agent sends frontend logs to AWS CloudWatch for:
# 1. ASR2 Compliance: Audit logs retention (90 days immutable)
# 2. Access Monitoring: Track HTTP requests and errors
# 3. Debugging: Centralized log aggregation for frontend
#
# Logs sent to CloudWatch:
# - /var/log/user-data.log     -> /arquisoft/django
# - /var/log/nginx/access.log  -> /arquisoft/django
# - /var/log/nginx/error.log   -> /arquisoft/django
# ============================================================================
echo "=== Installing CloudWatch Logs Agent ==="

# Download and install CloudWatch Logs Agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i -E ./amazon-cloudwatch-agent.deb

# Create CloudWatch Logs Agent configuration for Frontend
# This sends Nginx logs to CloudWatch
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
            "log_stream_name": "{instance_id}-frontend-setup",
            "retention_in_days": 90
          },
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "/arquisoft/django",
            "log_stream_name": "{instance_id}-nginx-access",
            "retention_in_days": 90
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "/arquisoft/django",
            "log_stream_name": "{instance_id}-nginx-error",
            "retention_in_days": 90
          }
        ]
      }
    }
  }
}
CWCONFIGEOF

echo "=== CloudWatch Logs Agent installed ==="
echo "Note: Agent will start after Nginx is running"

echo "=== Installing Node.js and npm ==="

# Install Node.js 18+ (using NodeSource repository)
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

# Verify Node.js and npm installation
node --version
npm --version

echo "=== Cloning Repository ==="

# Clone repo with GitHub token (then remove token from remote)
cd /home/ubuntu
git clone https://x-access-token:${github_token}@github.com/ARQUISOFT-202610/Sprint4.git /app
cd /app

# Remove token from remote URL
git remote set-url origin https://github.com/ARQUISOFT-202610/Sprint4.git

echo "=== Installing npm Dependencies ==="

# Install npm packages
cd /app
npm ci  # ci = clean install (preferred for deployments)

echo "=== Building React Application ==="

# Build the React application for production
npm run build

# Verify build directory exists
if [ ! -d "/app/build" ]; then
  echo "ERROR: Build directory not found!"
  exit 1
fi

# ============================================================================
# Install TLS Certificate
# ============================================================================
# The certificate and key are injected from Terraform variables
# They are placed in /etc/nginx/ssl for use by Nginx
# ============================================================================
echo "=== Installing TLS Certificate ==="

# Create SSL directory
mkdir -p /etc/nginx/ssl

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

echo "=== TLS Certificate installed ==="

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

    # React static files
    root /app/build;
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

# Enable the Nginx configuration
ln -sf /etc/nginx/sites-available/frontend /etc/nginx/sites-enabled/frontend
rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
nginx -t

# Enable and start Nginx
systemctl daemon-reload
systemctl enable nginx
systemctl start nginx

# ============================================================================
# Start CloudWatch Logs Agent
# ============================================================================
# Now that Nginx is running and creating logs, start the agent
# The agent will send logs to /arquisoft/django log group
echo "=== Starting CloudWatch Logs Agent ==="
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json \
  -s

echo "=== Verifying Services ==="

# Check if Nginx is running
if systemctl is-active --quiet nginx; then
    echo "✓ Nginx is running"
else
    echo "✗ Nginx failed to start"
    exit 1
fi

# Check if React build is served
if curl -s -k https://localhost/health | grep -q healthy; then
    echo "✓ Frontend health check passed (HTTPS)"
else
    echo "✗ Frontend health check failed"
    exit 1
fi

echo "=== Frontend Setup Completed ==="
date
echo "Frontend is now serving React application:"
echo "  HTTP  (redirects to HTTPS): http://localhost"
echo "  HTTPS (main endpoint):      https://localhost"
echo "Logs being sent to CloudWatch: /arquisoft/django"
