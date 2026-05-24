# ============================================================================
# TLS Self-Signed Certificate Module for ArquiSoft HTTPS
# ============================================================================
# Purpose: Generate a self-signed TLS certificate for HTTPS in development
# Valid for 365 days, suitable for frontend Nginx configuration
# ============================================================================

# Generate RSA 2048-bit private key
resource "tls_private_key" "arquisoft" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Generate self-signed certificate valid for 365 days
resource "tls_self_signed_cert" "arquisoft" {
  private_key_pem       = tls_private_key.arquisoft.private_key_pem
  validity_period_hours = 8760  # 365 days

  subject {
    common_name  = "arquisoft.local"
    organization = "ArquiSoft"
  }

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# Store certificate in local file (for reference/backup)
resource "local_file" "cert_pem" {
  content              = tls_self_signed_cert.arquisoft.cert_pem
  filename             = "${path.module}/../../.tls/arquisoft.crt"
  file_permission      = "0644"
  directory_permission = "0755"
}

# Store private key in local sensitive file (for reference/backup)
resource "local_sensitive_file" "key_pem" {
  content              = tls_private_key.arquisoft.private_key_pem
  filename             = "${path.module}/../../.tls/arquisoft.key"
  file_permission      = "0600"
  directory_permission = "0755"
}
