# ----- Empacota o codigo Python da Lambda -----
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../../environments/dr/lambda/failover.py"
  output_path = "${path.module}/failover.zip"
}

# ----- IAM: papel e permissoes minimas da Lambda -----
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project}-failover-lambda"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "perms" {
  statement {
    sid    = "PromoteReplica"
    effect = "Allow"
    actions = [
      "rds:PromoteReadReplica",
      "rds:DescribeDBInstances"
    ]
    resources = ["*"]
  }
  statement {
    sid    = "ScaleStandby"
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:DescribeAutoScalingGroups"
    ]
    resources = ["*"]
  }
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.project}-failover-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.perms.json
}

# ----- A funcao Lambda -----
resource "aws_lambda_function" "failover" {
  function_name    = "${var.project}-failover-controller"
  role             = aws_iam_role.lambda.arn
  handler          = "failover.handler"
  runtime          = "python3.12"
  timeout          = 120
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      STANDBY_ASG_NAME   = var.standby_asg_name
      DESIRED_CAPACITY   = tostring(var.standby_desired_capacity)
      REPLICA_IDENTIFIER = var.replica_identifier
      STANDBY_REGION     = var.standby_region
    }
  }
}

# ----- SNS: o alarme publica aqui e a Lambda subscreve -----
resource "aws_sns_topic" "failover" {
  name = "${var.project}-failover-topic"
}

resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = aws_sns_topic.failover.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.failover.arn
}

resource "aws_lambda_permission" "sns" {
  statement_id  = "AllowSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.failover.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.failover.arn
}

# ----- CloudWatch alarme sobre o health check do Route 53 -----
# HealthCheckStatus = 1 (saudavel) / 0 (nao saudavel).
# Se ficar a 0, o alarme dispara e publica no SNS -> Lambda.
resource "aws_cloudwatch_metric_alarm" "primary_down" {
  alarm_name          = "${var.project}-primary-region-down"
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  dimensions          = { HealthCheckId = var.health_check_id }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  alarm_actions       = [aws_sns_topic.failover.arn]
  treat_missing_data  = "breaching"
}
