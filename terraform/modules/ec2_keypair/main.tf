# ─────────────────────────────────────────
# EC2 Key Pair Generation
# ─────────────────────────────────────────
# Generates a new RSA key pair locally and uploads public key to AWS

# Generate a local private key
resource "tls_private_key" "arquisoft" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Create the key pair in AWS with the public key
resource "aws_key_pair" "arquisoft" {
  key_name   = var.key_name
  public_key = tls_private_key.arquisoft.public_key_openssh

  tags = merge(
    var.tags,
    {
      Name = "arquisoft-keypair"
    }
  )
}

# Save the private key locally using local_sensitive_file (not deprecated)
resource "local_sensitive_file" "private_key" {
  filename        = "${var.local_key_path}/${var.key_name}.pem"
  content         = tls_private_key.arquisoft.private_key_pem
  file_permission = "0400"
}

# Output the key pair name for reference
output "key_name" {
  description = "Name of the EC2 Key Pair"
  value       = aws_key_pair.arquisoft.key_name
}

# Output the private key path
output "private_key_path" {
  description = "Path to the private key file"
  value       = local_sensitive_file.private_key.filename
  sensitive   = true
}
