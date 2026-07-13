output "lambda_name" {
  value = aws_lambda_function.failover.function_name
}

output "sns_topic_arn" {
  value = aws_sns_topic.failover.arn
}

output "alarm_name" {
  value = aws_cloudwatch_metric_alarm.primary_down.alarm_name
}
