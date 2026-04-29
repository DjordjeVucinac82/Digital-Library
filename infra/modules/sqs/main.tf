# SQS module — creates the books-compressed queue and its dead-letter queue.
#
# Flow:
#   Compressor → books-compressed queue → Worker
#   After max_receive_count failed attempts → books-compressed-dlq
#
# The DLQ lets ops investigate messages that couldn't be processed.

locals {
  queue_name = "${var.queue_name}-${var.environment}"
  dlq_name   = "${var.queue_name}-dlq-${var.environment}"
}

# Dead-letter queue — receives messages that failed delivery max_receive_count times
resource "aws_sqs_queue" "dlq" {
  name                      = local.dlq_name
  message_retention_seconds = 1209600 # 14 days — keep failed messages longer for debugging

  tags = {
    Name        = local.dlq_name
    Environment = var.environment
    Purpose     = "Dead-letter queue for failed book compression messages"
  }
}

# Main queue — receives compressed book payloads from Compressor
resource "aws_sqs_queue" "main" {
  name                       = local.queue_name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds

  # Redirect to DLQ after max_receive_count failed processing attempts
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = {
    Name        = local.queue_name
    Environment = var.environment
    Purpose     = "Books compressed queue - compressor to worker"
  }
}
