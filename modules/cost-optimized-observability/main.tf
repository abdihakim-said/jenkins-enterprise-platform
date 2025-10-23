# Cost-Optimized Observability Module
# Runs on existing Jenkins infrastructure - saves ~$105/month vs ECS

# CloudWatch Dashboard for Jenkins metrics
resource "aws_cloudwatch_dashboard" "jenkins_observability" {
  dashboard_name = "${var.project_name}-${var.environment}-observability"

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
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", "${var.project_name}-${var.environment}-jenkins-asg"],
            [".", "NetworkIn", ".", "."],
            [".", "NetworkOut", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Jenkins Infrastructure Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", data.aws_lb.jenkins.arn_suffix],
            [".", "ResponseTime", ".", "."],
            [".", "HTTPCode_Target_2XX_Count", ".", "."],
            [".", "HTTPCode_Target_4XX_Count", ".", "."],
            [".", "HTTPCode_Target_5XX_Count", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Jenkins Application Performance"
          period  = 300
        }
      }
    ]
  })
}

# CloudWatch Alarms for critical metrics
resource "aws_cloudwatch_metric_alarm" "jenkins_high_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-jenkins-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors jenkins cpu utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    AutoScalingGroupName = "${var.project_name}-${var.environment}-jenkins-asg"
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "jenkins_high_response_time" {
  alarm_name          = "${var.project_name}-${var.environment}-jenkins-high-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = "2"
  alarm_description   = "This metric monitors jenkins response time"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = data.aws_lb.jenkins.arn_suffix
  }

  tags = local.common_tags
}

# SNS Topic for alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-observability-alerts"
  tags = local.common_tags
}

# S3 bucket for log aggregation (cost-optimized lifecycle)
resource "aws_s3_bucket" "logs" {
  bucket        = "${var.project_name}-${var.environment}-logs-${random_id.bucket_suffix.hex}"
  force_destroy = false
  tags          = local.common_tags
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "logs_lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365  # 1 year retention
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# CloudWatch Log Group for Jenkins application logs
resource "aws_cloudwatch_log_group" "jenkins_app" {
  name              = "/jenkins/${var.environment}/application"
  retention_in_days = 30
  tags              = local.common_tags
}

# CloudWatch Log Group for system logs
resource "aws_cloudwatch_log_group" "jenkins_system" {
  name              = "/jenkins/${var.environment}/system"
  retention_in_days = 14
  tags              = local.common_tags
}

# Custom CloudWatch metrics for Jenkins jobs
resource "aws_cloudwatch_log_metric_filter" "jenkins_job_success" {
  name           = "${var.project_name}-${var.environment}-jenkins-job-success"
  log_group_name = aws_cloudwatch_log_group.jenkins_app.name
  pattern        = "[timestamp, level=\"INFO\", message=\"Build successful\"]"

  metric_transformation {
    name      = "JenkinsJobSuccess"
    namespace = "Jenkins/Jobs"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "jenkins_job_failure" {
  name           = "${var.project_name}-${var.environment}-jenkins-job-failure"
  log_group_name = aws_cloudwatch_log_group.jenkins_app.name
  pattern        = "[timestamp, level=\"ERROR\", message=\"Build failed\"]"

  metric_transformation {
    name      = "JenkinsJobFailure"
    namespace = "Jenkins/Jobs"
    value     = "1"
  }
}

# Data sources
data "aws_lb" "jenkins" {
  name = "${var.environment}-jenkins-alb"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Local values
locals {
  common_tags = {
    Name        = "${var.project_name}-${var.environment}-cost-optimized-observability"
    Environment = var.environment
    Project     = var.project_name
    Module      = "cost-optimized-observability"
    ManagedBy   = "Terraform"
    CreatedBy   = "Terraform"
    Owner       = "DevOps Team"
    Epic        = "Epic-2-Golden-Image"
    CostCenter  = "DevOps"
    Purpose     = "Cost-optimized observability and monitoring"
  }
}
