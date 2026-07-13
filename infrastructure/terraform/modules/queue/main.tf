resource "aws_sqs_queue" "order_dlq" {
  name                      = "${var.project}-${var.environment}-order-dlq"
  message_retention_seconds = 1209600

  tags = {
    Name = "${var.project}-${var.environment}-order-dlq"
  }
}

resource "aws_sqs_queue" "order_created" {
  name                       = "${var.project}-${var.environment}-order-created"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.order_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = "${var.project}-${var.environment}-order-created"
  }
}