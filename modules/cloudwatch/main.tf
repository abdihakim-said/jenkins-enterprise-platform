# CloudWatch Module - Main Configuration
# Author: Abdihakim Said

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "jenkins_application" {
  name              = "/jenkins/${var.environment}/application"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, {
    Name = "/jenkins/${var.environment}/application"
    Type = "Jenkins Application Logs"
  })
}

resource "aws_cloudwatch_log_group" "jenkins_user_data" {
  name              = "/jenkins/${var.environment}/user-data"
  retention_in_days = 7
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, {
    Name = "/jenkins/${var.environment}/user-data"
    Type = "Jenkins User Data Logs"
  })
}

resource "aws_cloudwatch_log_group" "jenkins_system" {
  name              = "/jenkins/${var.environment}/system"
  retention_in_days = 14
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, {
    Name = "/jenkins/${var.environment}/system"
    Type = "Jenkins System Logs"
  })
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "jenkins" {
  dashboard_name = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-dashboard"

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
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", "${var.environment}-${replace(lower(var.project_name), " ", "-")}-asg"],
            [".", "NetworkIn", ".", "."],
            [".", "NetworkOut", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "EC2 Instance Metrics"
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
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "${var.environment}-${replace(lower(var.project_name), " ", "-")}-alb"],
            [".", "TargetResponseTime", ".", "."],
            [".", "HTTPCode_Target_2XX_Count", ".", "."],
            [".", "HTTPCode_Target_4XX_Count", ".", "."],
            [".", "HTTPCode_Target_5XX_Count", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Application Load Balancer Metrics"
          period  = 300
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 12
        width  = 24
        height = 6

        properties = {
          query   = "SOURCE '/jenkins/${var.environment}/application' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          region  = data.aws_region.current.name
          title   = "Recent Jenkins Application Logs"
        }
      }
    ]
  })
}

# CloudWatch Alarms for Jenkins Health
resource "aws_cloudwatch_metric_alarm" "jenkins_high_error_rate" {
  alarm_name          = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors Jenkins 5XX error rate"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-alb"
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "jenkins_high_response_time" {
  alarm_name          = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-high-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = "5"
  alarm_description   = "This metric monitors Jenkins response time"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-alb"
  }

  tags = var.tags
}

# SNS Topic for Alerts (optional)
resource "aws_sns_topic" "jenkins_alerts" {
  name              = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-alerts"
  kms_master_key_id = var.kms_key_id

  tags = merge(var.tags, {
    Name = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-alerts"
    Type = "Jenkins Alerts Topic"
  })
}

# Data source
data "aws_region" "current" {}
