# Automatic Vertical Scaling Configuration
# Scales instance type based on CPU/Memory metrics

# Mixed instance policy for automatic vertical scaling
locals {
  # Instance types in order of size (auto-scales up/down)
  instance_types = [
    "t3.small",  # 2 vCPU, 2GB RAM - $15/month
    "t3.medium", # 2 vCPU, 4GB RAM - $30/month
    "t3.large",  # 2 vCPU, 8GB RAM - $60/month
  ]
}

# CloudWatch alarm for high memory (scale up)
resource "aws_cloudwatch_metric_alarm" "high_memory_scale_up" {
  alarm_name          = "${var.project_name}-${var.environment}-high-memory-scale-up"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "CWAgent"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Trigger vertical scaling when memory > 80%"
  alarm_actions       = [aws_sns_topic.deployment_notifications.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.blue.name
  }
}

# CloudWatch alarm for high CPU (scale up)
resource "aws_cloudwatch_metric_alarm" "high_cpu_scale_up" {
  alarm_name          = "${var.project_name}-${var.environment}-high-cpu-scale-up"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 75
  alarm_description   = "Trigger vertical scaling when CPU > 75%"
  alarm_actions       = [aws_sns_topic.deployment_notifications.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.blue.name
  }
}

# Lambda function for automatic vertical scaling
resource "aws_lambda_function" "vertical_scaler" {
  filename      = "${path.module}/vertical_scaler.zip"
  function_name = "${var.project_name}-${var.environment}-vertical-scaler"
  role          = aws_iam_role.vertical_scaler_role.arn
  handler       = "vertical_scaler.lambda_handler"
  runtime       = "python3.9"
  timeout       = 300
  memory_size   = 256

  environment {
    variables = {
      BLUE_ASG_NAME  = aws_autoscaling_group.blue.name
      GREEN_ASG_NAME = aws_autoscaling_group.green.name
      INSTANCE_TYPES = jsonencode(local.instance_types)
      SNS_TOPIC_ARN  = aws_sns_topic.deployment_notifications.arn
    }
  }

  tags = merge(var.common_tags, {
    Name = "Vertical Scaler"
  })
}

# IAM role for vertical scaler Lambda
resource "aws_iam_role" "vertical_scaler_role" {
  name = "${var.project_name}-${var.environment}-vertical-scaler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# IAM policy for vertical scaler
resource "aws_iam_role_policy" "vertical_scaler_policy" {
  name = "${var.project_name}-${var.environment}-vertical-scaler-policy"
  role = aws_iam_role.vertical_scaler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:UpdateAutoScalingGroup",
          "ec2:DescribeLaunchTemplates",
          "ec2:CreateLaunchTemplateVersion",
          "ec2:DescribeInstances",
          "cloudwatch:GetMetricStatistics",
          "sns:Publish",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# EventBridge rule to trigger vertical scaling check
resource "aws_cloudwatch_event_rule" "vertical_scaling_check" {
  name                = "${var.project_name}-${var.environment}-vertical-scaling-check"
  description         = "Check if vertical scaling is needed every 10 minutes"
  schedule_expression = "rate(10 minutes)"
}

# EventBridge target
resource "aws_cloudwatch_event_target" "vertical_scaler_target" {
  rule      = aws_cloudwatch_event_rule.vertical_scaling_check.name
  target_id = "VerticalScalerTarget"
  arn       = aws_lambda_function.vertical_scaler.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_vertical_scaler" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.vertical_scaler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.vertical_scaling_check.arn
}
