# Jenkins Cost Optimization Module
# Author: Abdihakim Said
# Implements intelligent cost management with S3 storage and automation

# S3 Bucket for Cost Reports and Analytics
resource "aws_s3_bucket" "cost_reports" {
  bucket = "${var.environment}-jenkins-cost-optimization-${random_string.bucket_suffix.result}"
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-jenkins-cost-reports"
    Purpose = "Cost Optimization Analytics"
    CostCenter = "DevOps"
  })
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# S3 Bucket Configuration
resource "aws_s3_bucket_versioning" "cost_reports" {
  bucket = aws_s3_bucket.cost_reports.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cost_reports" {
  bucket = aws_s3_bucket.cost_reports.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle policy for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "cost_reports" {
  bucket = aws_s3_bucket.cost_reports.id
  
  rule {
    id     = "cost_reports_lifecycle"
    status = "Enabled"
    
    filter {
      prefix = "cost-reports/"
    }
    
    # Daily reports
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    
    expiration {
      days = 2555  # 7 years retention
    }
  }
}

# Cost Budget with Alerts
resource "aws_budgets_budget" "jenkins_cost_budget" {
  name         = "${var.environment}-jenkins-cost-budget"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  
  cost_filter {
    name   = "TagKeyValue"
    values = ["Project$jenkins-enterprise-platform"]
  }
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 50
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = [var.cost_alert_email]
  }
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.cost_alert_email]
  }
}

# SNS Topic for Cost Alerts
resource "aws_sns_topic" "cost_alerts" {
  name = "${var.environment}-jenkins-cost-alerts"
  
  tags = var.common_tags
}

resource "aws_sns_topic_subscription" "cost_email_alerts" {
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = var.cost_alert_email
}

# Lambda for Cost Optimization
resource "aws_lambda_function" "cost_optimizer" {
  filename         = data.archive_file.cost_optimizer_zip.output_path
  function_name    = "${var.environment}-jenkins-cost-optimizer"
  role            = aws_iam_role.cost_optimizer_role.arn
  handler         = "cost_optimizer.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300
  
  environment {
    variables = {
      ENVIRONMENT = var.environment
      ASG_NAME    = var.jenkins_asg_name
      SNS_TOPIC   = aws_sns_topic.cost_alerts.arn
      S3_BUCKET   = aws_s3_bucket.cost_reports.bucket
      JENKINS_URL = var.jenkins_url
    }
  }
  
  tags = var.common_tags
}

# CloudWatch Event for Cost Optimization (every hour)
resource "aws_cloudwatch_event_rule" "cost_optimization_schedule" {
  name                = "${var.environment}-cost-optimization"
  description         = "Trigger Jenkins cost optimization every hour"
  schedule_expression = "rate(1 hour)"
}

resource "aws_cloudwatch_event_target" "cost_optimizer_target" {
  rule      = aws_cloudwatch_event_rule.cost_optimization_schedule.name
  target_id = "CostOptimizerTarget"
  arn       = aws_lambda_function.cost_optimizer.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_optimizer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cost_optimization_schedule.arn
}

# Scheduled Scaling for Off-Hours
resource "aws_autoscaling_schedule" "scale_down_evening" {
  scheduled_action_name  = "${var.environment}-jenkins-scale-down"
  min_size              = 0
  max_size              = 1
  desired_capacity      = 0
  recurrence            = "0 19 * * MON-FRI"  # 7 PM weekdays
  autoscaling_group_name = var.jenkins_asg_name
}

resource "aws_autoscaling_schedule" "scale_up_morning" {
  scheduled_action_name  = "${var.environment}-jenkins-scale-up"
  min_size              = 1
  max_size              = 5
  desired_capacity      = 1
  recurrence            = "0 8 * * MON-FRI"   # 8 AM weekdays
  autoscaling_group_name = var.jenkins_asg_name
}

# Weekend scaling
resource "aws_autoscaling_schedule" "scale_down_weekend" {
  scheduled_action_name  = "${var.environment}-jenkins-weekend-down"
  min_size              = 0
  max_size              = 1
  desired_capacity      = 0
  recurrence            = "0 20 * * FRI"      # Friday 8 PM
  autoscaling_group_name = var.jenkins_asg_name
}

resource "aws_autoscaling_schedule" "scale_up_monday" {
  scheduled_action_name  = "${var.environment}-jenkins-monday-up"
  min_size              = 1
  max_size              = 5
  desired_capacity      = 1
  recurrence            = "0 8 * * MON"       # Monday 8 AM
  autoscaling_group_name = var.jenkins_asg_name
}

# IAM Role for Cost Optimizer Lambda
resource "aws_iam_role" "cost_optimizer_role" {
  name = "${var.environment}-jenkins-cost-optimizer-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = var.common_tags
}

resource "aws_iam_role_policy" "cost_optimizer_policy" {
  name = "${var.environment}-jenkins-cost-optimizer-policy"
  role = aws_iam_role.cost_optimizer_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:SetDesiredCapacity",
          "ec2:DescribeInstances",
          "ec2:DescribeSpotInstanceRequests",
          "ec2:DescribeSpotPriceHistory",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:PutMetricData",
          "sns:Publish",
          "s3:PutObject",
          "s3:GetObject",
          "budgets:ViewBudget"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cost_optimizer_basic" {
  role       = aws_iam_role.cost_optimizer_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# CloudWatch Dashboard for Cost Monitoring
resource "aws_cloudwatch_dashboard" "cost_optimization" {
  dashboard_name = "${var.environment}-jenkins-cost-optimization"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", var.jenkins_asg_name],
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", var.jenkins_asg_name]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Jenkins Workers - Cost Optimization"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        
        properties = {
          query   = "SOURCE '/aws/lambda/${aws_lambda_function.cost_optimizer.function_name}' | fields @timestamp, @message | filter @message like /COST/ | sort @timestamp desc | limit 100"
          region  = data.aws_region.current.name
          title   = "Cost Optimization Events"
        }
      }
    ]
  })
}

# Data sources
data "aws_region" "current" {}

data "archive_file" "cost_optimizer_zip" {
  type        = "zip"
  output_path = "${path.module}/cost_optimizer.zip"
  source_file = "${path.module}/cost_optimizer.py"
}
