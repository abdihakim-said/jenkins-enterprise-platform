# Jenkins Enterprise Platform - Monitoring and Alerting
# Comprehensive monitoring setup for production readiness
# Date: 2025-08-17

# CloudWatch Alarms for Jenkins Infrastructure

# CPU Utilization Alarm
resource "aws_cloudwatch_metric_alarm" "jenkins_cpu_high" {
  alarm_name          = "jenkins-cpu-utilization-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors jenkins instance cpu utilization"
  alarm_actions       = [aws_sns_topic.jenkins_alerts.arn]
  ok_actions          = [aws_sns_topic.jenkins_alerts.arn]

  dimensions = {
    AutoScalingGroupName = "staging-jenkins-asg"
  }

  tags = {
    Name        = "Jenkins-CPU-High"
    Environment = "staging"
    Project     = "Jenkins-Enterprise-Platform"
  }
}

# Memory Utilization Alarm
resource "aws_cloudwatch_metric_alarm" "jenkins_memory_high" {
  alarm_name          = "jenkins-memory-utilization-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "mem_used_percent"
  namespace           = "Jenkins/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors jenkins instance memory utilization"
  alarm_actions       = [aws_sns_topic.jenkins_alerts.arn]
  ok_actions          = [aws_sns_topic.jenkins_alerts.arn]

  dimensions = {
    AutoScalingGroupName = "staging-jenkins-asg"
  }

  tags = {
    Name        = "Jenkins-Memory-High"
    Environment = "staging"
    Project     = "Jenkins-Enterprise-Platform"
  }
}

# Disk Utilization Alarm
resource "aws_cloudwatch_metric_alarm" "jenkins_disk_high" {
  alarm_name          = "jenkins-disk-utilization-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "used_percent"
  namespace           = "Jenkins/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors jenkins instance disk utilization"
  alarm_actions       = [aws_sns_topic.jenkins_alerts.arn]
  ok_actions          = [aws_sns_topic.jenkins_alerts.arn]

  dimensions = {
    AutoScalingGroupName = "staging-jenkins-asg"
    device               = "/dev/sda1"
    fstype               = "ext4"
    path                 = "/"
  }

  tags = {
    Name        = "Jenkins-Disk-High"
    Environment = "staging"
    Project     = "Jenkins-Enterprise-Platform"
  }
}

# Application Load Balancer Target Health
resource "aws_cloudwatch_metric_alarm" "jenkins_unhealthy_targets" {
  alarm_name          = "jenkins-unhealthy-targets"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors healthy targets in Jenkins target group"
  alarm_actions       = [aws_sns_topic.jenkins_alerts.arn]
  ok_actions          = [aws_sns_topic.jenkins_alerts.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    TargetGroup  = "targetgroup/staging-jenkins-tg/ba3e9eb296b6f5d5"
    LoadBalancer = "app/staging-jenkins-alb/737d8003853cb795"
  }

  tags = {
    Name        = "Jenkins-Unhealthy-Targets"
    Environment = "staging"
    Project     = "Jenkins-Enterprise-Platform"
  }
}

# Application Load Balancer Response Time
resource "aws_cloudwatch_metric_alarm" "jenkins_response_time_high" {
  alarm_name          = "jenkins-response-time-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = "5"
  alarm_description   = "This metric monitors Jenkins response time"
  alarm_actions       = [aws_sns_topic.jenkins_alerts.arn]
  ok_actions          = [aws_sns_topic.jenkins_alerts.arn]

  dimensions = {
    LoadBalancer = "app/staging-jenkins-alb/737d8003853cb795"
  }

  tags = {
    Name        = "Jenkins-Response-Time-High"
    Environment = "staging"
    Project     = "Jenkins-Enterprise-Platform"
  }
}

# Jenkins Queue Length (Custom Metric)
resource "aws_cloudwatch_metric_alarm" "jenkins_queue_length_high" {
  alarm_name          = "jenkins-queue-length-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "jenkins_queue_size_value"
  namespace           = "Jenkins/Application"
  period              = "300"
  statistic           = "Average"
  threshold           = "10"
  alarm_description   = "This metric monitors Jenkins build queue length"
  alarm_actions       = [aws_sns_topic.jenkins_alerts.arn]
  ok_actions          = [aws_sns_topic.jenkins_alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = {
    Name        = "Jenkins-Queue-Length-High"
    Environment = "staging"
    Project     = "Jenkins-Enterprise-Platform"
  }
}

# SNS Topic for Jenkins Alerts
resource "aws_sns_topic" "jenkins_alerts" {
  name = "jenkins-alerts"

  tags = {
    Name        = "Jenkins-Alerts-Topic"
    Environment = "staging"
    Project     = "Jenkins-Enterprise-Platform"
  }
}

# SNS Topic Subscription for Email Alerts
resource "aws_sns_topic_subscription" "jenkins_email_alerts" {
  topic_arn = aws_sns_topic.jenkins_alerts.arn
  protocol  = "email"
  endpoint  = "devops-team@company.com"  # Replace with actual email
}

# SNS Topic Subscription for Slack (if using)
resource "aws_sns_topic_subscription" "jenkins_slack_alerts" {
  topic_arn = aws_sns_topic.jenkins_alerts.arn
  protocol  = "https"
  endpoint  = "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"  # Replace with actual webhook
}

# CloudWatch Dashboard for Jenkins
resource "aws_cloudwatch_dashboard" "jenkins_dashboard" {
  dashboard_name = "Jenkins-Enterprise-Platform"

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
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", "staging-jenkins-asg"],
            ["Jenkins/EC2", "mem_used_percent", "AutoScalingGroupName", "staging-jenkins-asg"],
            ["Jenkins/EC2", "used_percent", "AutoScalingGroupName", "staging-jenkins-asg", "device", "/dev/sda1", "fstype", "ext4", "path", "/"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          title   = "Jenkins Instance Metrics"
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
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", "targetgroup/staging-jenkins-tg/ba3e9eb296b6f5d5", "LoadBalancer", "app/staging-jenkins-alb/737d8003853cb795"],
            [".", "UnHealthyHostCount", ".", ".", ".", "."],
            [".", "TargetResponseTime", "LoadBalancer", "app/staging-jenkins-alb/737d8003853cb795"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          title   = "Load Balancer Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["Jenkins/Application", "jenkins_queue_size_value"],
            [".", "jenkins_executor_count_value"],
            [".", "jenkins_job_count_value"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          title   = "Jenkins Application Metrics"
          period  = 300
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 18
        width  = 24
        height = 6

        properties = {
          query   = "SOURCE '/aws/ec2/jenkins' | fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20"
          region  = "us-east-1"
          title   = "Jenkins Error Logs"
          view    = "table"
        }
      }
    ]
  })
}

# EventBridge Rule for Auto Scaling Events
resource "aws_cloudwatch_event_rule" "jenkins_asg_events" {
  name        = "jenkins-asg-events"
  description = "Capture Auto Scaling events for Jenkins"

  event_pattern = jsonencode({
    source      = ["aws.autoscaling"]
    detail-type = ["EC2 Instance Launch Successful", "EC2 Instance Launch Unsuccessful", "EC2 Instance Terminate Successful", "EC2 Instance Terminate Unsuccessful"]
    detail = {
      AutoScalingGroupName = ["staging-jenkins-asg"]
    }
  })

  tags = {
    Name        = "Jenkins-ASG-Events"
    Environment = "staging"
    Project     = "Jenkins-Enterprise-Platform"
  }
}

# EventBridge Target for SNS
resource "aws_cloudwatch_event_target" "jenkins_asg_sns" {
  rule      = aws_cloudwatch_event_rule.jenkins_asg_events.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.jenkins_alerts.arn
}

# Lambda function for custom Jenkins metrics collection
resource "aws_lambda_function" "jenkins_metrics_collector" {
  filename         = "jenkins_metrics_collector.zip"
  function_name    = "jenkins-metrics-collector"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = 60

  environment {
    variables = {
      JENKINS_URL = "http://staging-jenkins-alb-1353461168.us-east-1.elb.amazonaws.com:8080"
      CLOUDWATCH_NAMESPACE = "Jenkins/Application"
    }
  }

  tags = {
    Name        = "Jenkins-Metrics-Collector"
    Environment = "staging"
    Project     = "Jenkins-Enterprise-Platform"
  }
}

# Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "jenkins_metrics_collector.zip"
  source {
    content = <<EOF
import json
import boto3
import urllib3
import os
from datetime import datetime

def handler(event, context):
    jenkins_url = os.environ['JENKINS_URL']
    namespace = os.environ['CLOUDWATCH_NAMESPACE']
    
    http = urllib3.PoolManager()
    cloudwatch = boto3.client('cloudwatch')
    
    try:
        # Get Jenkins API data
        response = http.request('GET', f'{jenkins_url}/api/json?tree=jobs[name],executors[*],queue[*]')
        data = json.loads(response.data.decode('utf-8'))
        
        # Extract metrics
        job_count = len(data.get('jobs', []))
        queue_size = len(data.get('queue', []))
        executor_count = len(data.get('executors', []))
        
        # Send metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace=namespace,
            MetricData=[
                {
                    'MetricName': 'jenkins_job_count_value',
                    'Value': job_count,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'jenkins_queue_size_value',
                    'Value': queue_size,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'jenkins_executor_count_value',
                    'Value': executor_count,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps('Metrics sent successfully')
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
EOF
    filename = "index.py"
  }
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "jenkins-metrics-lambda-role"

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
}

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  name = "jenkins-metrics-lambda-policy"
  role = aws_iam_role.lambda_role.id

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
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Event Rule to trigger Lambda every 5 minutes
resource "aws_cloudwatch_event_rule" "jenkins_metrics_schedule" {
  name                = "jenkins-metrics-schedule"
  description         = "Trigger Jenkins metrics collection every 5 minutes"
  schedule_expression = "rate(5 minutes)"

  tags = {
    Name        = "Jenkins-Metrics-Schedule"
    Environment = "staging"
    Project     = "Jenkins-Enterprise-Platform"
  }
}

# CloudWatch Event Target for Lambda
resource "aws_cloudwatch_event_target" "jenkins_metrics_lambda_target" {
  rule      = aws_cloudwatch_event_rule.jenkins_metrics_schedule.name
  target_id = "JenkinsMetricsLambdaTarget"
  arn       = aws_lambda_function.jenkins_metrics_collector.arn
}

# Lambda permission for CloudWatch Events
resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.jenkins_metrics_collector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.jenkins_metrics_schedule.arn
}

# Output monitoring resources
output "sns_topic_arn" {
  description = "ARN of the SNS topic for Jenkins alerts"
  value       = aws_sns_topic.jenkins_alerts.arn
}

output "dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=${aws_cloudwatch_dashboard.jenkins_dashboard.dashboard_name}"
}
