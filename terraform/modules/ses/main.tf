# ============================================================================
# AWS SES Module - Email Service for ArquiSoft Application
# ============================================================================
# Purpose: Configure Simple Email Service (SES) for sending email
# notifications about analysis results (success/failure) via Celery.
# Supports ASR1 requirement: Notifications for background analysis completion.
# 
# IMPORTANT - SES Email Verification (AWS Academy Sandbox Mode):
# ============================================================================
# In AWS Academy accounts, SES is in "SANDBOX MODE" by default, which means:
# 1. You can ONLY send emails from verified email addresses
# 2. You can ONLY send emails to verified email addresses
# 3. You have a sending limit of 200 emails/day
#
# REQUIRED STEPS (Manual AWS Console - cannot be automated):
# A. Verify Sender Email (Gmail):
#    1. Go to AWS Console > SES > Verified Identities
#    2. Click "Create Identity" > Email address
#    3. Enter: noreply@arquisoft.com (or your Gmail)
#    4. Check Gmail inbox for verification link
#    5. Click link to verify
#
# B. Verify Recipient Email:
#    1. Go to AWS Console > SES > Verified Identities
#    2. Click "Create Identity" > Email address
#    3. Enter: c.ochoao@uniandes.edu.co
#    4. Check email inbox for verification link
#    5. Click link to verify
#
# After both emails are verified, SES can send to them automatically.
# ============================================================================

# Email Identity (Sender)
# NOTE: This will CREATE the identity but NOT automatically verify it.
# Manual verification is required (see instructions above).
resource "aws_ses_email_identity" "sender" {
  count = var.enable_email_verification ? 1 : 0
  email = var.sender_email
}

# Email Identity (Recipient)
# NOTE: This will CREATE the identity but NOT automatically verify it.
# Manual verification is required (see instructions above).
resource "aws_ses_email_identity" "recipient" {
  count = var.enable_email_verification ? 1 : 0
  email = var.recipient_email
}

# ============================================================================
# Email Templates for Analysis Results
# ============================================================================

# Template 1: Success Email
# Sent when background analysis completes successfully
resource "aws_ses_template" "success" {
  count = var.enable_templates ? 1 : 0

  name = var.success_template_name

  html = templatefile("${path.module}/templates/success_email.html", {})
  text = templatefile("${path.module}/templates/success_email.txt", {})

  subject = "ArquiSoft: Análisis Completado Exitosamente"
}

# Template 2: Failure Email
# Sent when background analysis fails or encounters errors
resource "aws_ses_template" "failure" {
  count = var.enable_templates ? 1 : 0

  name = var.failure_template_name

  html = templatefile("${path.module}/templates/failure_email.html", {})
  text = templatefile("${path.module}/templates/failure_email.txt", {})

  subject = "ArquiSoft: Análisis Completado con Errores"
}
