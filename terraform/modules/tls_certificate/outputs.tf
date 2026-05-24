# ============================================================================
# TLS Certificate Module - Outputs
# ============================================================================

output "certificate_pem" {
  description = "Self-signed TLS certificate in PEM format"
  value       = tls_self_signed_cert.arquisoft.cert_pem
}

output "private_key_pem" {
  description = "Private key for TLS certificate in PEM format (sensitive)"
  value       = tls_private_key.arquisoft.private_key_pem
  sensitive   = true
}

output "certificate_file" {
  description = "Path to certificate file saved locally"
  value       = local_file.cert_pem.filename
}

output "private_key_file" {
  description = "Path to private key file saved locally"
  value       = local_sensitive_file.key_pem.filename
}
