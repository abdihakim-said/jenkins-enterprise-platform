# Cost-Optimized Observability Module
# Author: Abdihakim Said
# Enhanced Enterprise Monitoring - saves ~$105/month vs ECS

# Enhanced Enterprise CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "jenkins_observability" {
  dashboard_name = "${var.project_name}-${var.environment}-enterprise-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # Infrastructure Health Overview
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", "jenkins-enterprise-platform-dev-blue-asg"],
            [".", "StatusCheckFailed", ".", "."],
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", "dev-jenkins-tg", "LoadBalancer", data.aws_lb.jenkins.arn_suffix],
            [".", "UnHealthyHostCount", ".", ".", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "🏗️ Infrastructure Health"
          period  = 300
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },

      # Application Performance
      {
        type   = "metric"
        x      = 8
        y      = 0
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", data.aws_lb.jenkins.arn_suffix],
            [".", "TargetResponseTime", ".", "."],
            [".", "HTTPCode_Target_2XX_Count", ".", "."],
            [".", "HTTPCode_Target_4XX_Count", ".", "."],
            [".", "HTTPCode_Target_5XX_Count", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "🚀 Application Performance"
          period  = 300
        }
      },

      # Cost Optimization Metrics
      {
        type   = "metric"
        x      = 16
        y      = 0
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Billing", "EstimatedCharges", "Currency", "USD"],
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", "jenkins-enterprise-platform-dev-blue-asg"],
            ["AWS/EFS", "StorageBytes", "StorageClass", "Total", "FileSystemId", data.aws_efs_file_system.jenkins.id]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "💰 Cost Optimization"
          period  = 3600
          stat    = "Maximum"
        }
      },

      # EFS Performance & Storage
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EFS", "DataReadIOBytes", "FileSystemId", data.aws_efs_file_system.jenkins.id],
            ["AWS/EFS", "DataWriteIOBytes", "FileSystemId", data.aws_efs_file_system.jenkins.id],
            ["AWS/EFS", "ClientConnections", "FileSystemId", data.aws_efs_file_system.jenkins.id],
            ["AWS/EFS", "PercentIOLimit", "FileSystemId", data.aws_efs_file_system.jenkins.id],
            ["AWS/EFS", "StorageBytes", "StorageClass", "Total", "FileSystemId", data.aws_efs_file_system.jenkins.id]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "💾 EFS Storage Performance"
          period  = 300
        }
      },

      # Blue/Green Deployment Status
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", "jenkins-enterprise-platform-dev-blue-asg"],
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", "jenkins-enterprise-platform-dev-blue-asg"],
            ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", "jenkins-enterprise-platform-dev-green-asg"],
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", "jenkins-enterprise-platform-dev-green-asg"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "🔄 Blue/Green Deployment Status"
          period  = 300
          annotations = {
            horizontal = [
              {
                label = "Target Capacity"
                value = 1
              }
            ]
          }
        }
      },

      # Security & Compliance
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", data.aws_lb.jenkins.arn_suffix],
            [".", "HTTPCode_Target_5XX_Count", ".", "."],
            ["AWS/EC2", "StatusCheckFailed_Instance", "AutoScalingGroupName", "jenkins-enterprise-platform-dev-blue-asg"],
            [".", "StatusCheckFailed_System", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "🛡️ Security & Health Checks"
          period  = 300
        }
      },

      # SLA & Uptime Tracking
      {
        type   = "metric"
        x      = 8
        y      = 12
        width  = 16
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", data.aws_lb.jenkins.arn_suffix],
            [".", "HTTPCode_Target_2XX_Count", ".", "."]
          ]
          view   = "singleValue"
          region = var.aws_region
          title  = "📊 SLA Metrics (99.9% Target)"
          period = 300
          stat   = "Average"
        }
      }
    ]
  })
}

# Enhanced CloudWatch Alarms for Enterprise Monitoring
resource "aws_cloudwatch_metric_alarm" "efs_high_io" {
  alarm_name          = "${var.project_name}-${var.environment}-efs-high-io"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "PercentIOLimit"
  namespace           = "AWS/EFS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "EFS IO utilization is high - may impact Jenkins performance"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FileSystemId = data.aws_efs_file_system.jenkins.id
  }

  tags = {
    Name        = "EFS High IO Alarm"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "jenkins_high_load" {
  alarm_name          = "${var.project_name}-${var.environment}-high-load"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RequestCount"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "100"
  alarm_description   = "High request volume - potential build queue backup"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = data.aws_lb.jenkins.arn_suffix
  }

  tags = {
    Name        = "Jenkins High Load Alarm"
    Environment = var.environment
    Project     = var.project_name
  }
}

# SNS Topic for Enhanced Alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-enhanced-alerts"

  tags = {
    Name        = "Enhanced Monitoring Alerts"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Data sources for existing resources
data "aws_lb" "jenkins" {
  name = "dev-jenkins-alb"
}

data "aws_efs_file_system" "jenkins" {
  file_system_id = "fs-0a1c496937c7252d3"
}
