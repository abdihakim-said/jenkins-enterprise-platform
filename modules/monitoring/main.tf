# SNS Topic for alerts
resource "aws_sns_topic" "jenkins_alerts" {
  name = var.sns_topic_name

  tags = merge(var.common_tags, {
    Name = var.sns_topic_name
    Purpose = "Jenkins Alerts"
  })
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.environment}-jenkins-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_sns_topic.jenkins_alerts.arn]

  dimensions = {
    AutoScalingGroupName = var.jenkins_asg_name
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-jenkins-high-cpu"
  })
}

resource "aws_cloudwatch_metric_alarm" "high_memory" {
  alarm_name          = "${var.environment}-jenkins-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "mem_used_percent"
  namespace           = "CWAgent"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors memory utilization"
  alarm_actions       = [aws_sns_topic.jenkins_alerts.arn]

  dimensions = {
    AutoScalingGroupName = var.jenkins_asg_name
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-jenkins-high-memory"
  })
}
