resource "aws_sqs_queue" "celery_queue" {
  name                      = var.queue_name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  delay_seconds             = var.delay_seconds
  receive_wait_time_seconds = var.receive_wait_time_seconds

  tags = var.tags
}
