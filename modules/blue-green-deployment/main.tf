# Enterprise Blue/Green Deployment Module for Jenkins Platform
# Author: Abdihakim Said
# Features: Zero-downtime, automated rollback, health checks, canary deployments

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  common_tags = merge(var.common_tags, {
    Module = "enterprise-blue-green-deployment"
  })
  
  # Deployment strategy configuration
  active_color   = var.active_deployment
  inactive_color = var.active_deployment == "blue" ? "green" : "blue"
  
  # Enterprise naming convention
  blue_name_prefix  = "${var.project_name}-${var.environment}-blue"
  green_name_prefix = "${var.project_name}-${var.environment}-green"
}

# Data source for latest Jenkins Golden AMI
data "aws_ami" "jenkins_golden" {
  most_recent = true
  owners      = ["self"]
  
  filter {
    name   = "name"
    values = ["jenkins-golden-ami-*"]
  }
}

# SNS Topic for deployment notifications
resource "aws_sns_topic" "deployment_notifications" {
  name              = "${var.project_name}-${var.environment}-deployment-alerts"
  kms_master_key_id = var.kms_key_id
  
  tags = merge(local.common_tags, {
    Name = "Deployment Notifications"
  })
}

# CloudWatch Log Group for deployment logs
resource "aws_cloudwatch_log_group" "deployment_logs" {
  name              = "/aws/jenkins/${var.environment}/blue-green-deployment"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn
  
  tags = local.common_tags
}

# Blue Environment Launch Template
resource "aws_launch_template" "blue" {
  name_prefix   = "${local.blue_name_prefix}-lt-"
  image_id      = var.blue_ami_id != "" ? var.blue_ami_id : data.aws_ami.jenkins_golden.id
  instance_type = var.instance_type
  
  vpc_security_group_ids = [var.security_group_id]
  
  iam_instance_profile {
    name = var.iam_instance_profile
  }
  
  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume_size
      iops                  = 3000
      throughput            = 125
      encrypted             = true
      delete_on_termination = true
    }
  }
  
  monitoring {
    enabled = true
  }
  
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 1
  }
  
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    efs_file_system_id = var.efs_file_system_id
    aws_region         = var.aws_region
    environment        = var.environment
    deployment_color   = "blue"
    log_group_name     = aws_cloudwatch_log_group.deployment_logs.name
    sns_topic_arn      = aws_sns_topic.deployment_notifications.arn
    health_check_url   = var.health_check_url
  }))
  
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name            = "${local.blue_name_prefix}-instance"
      DeploymentColor = "blue"
      HealthCheck     = "enabled"
    })
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.blue_name_prefix}-launch-template"
  })
}

# Green Environment Launch Template
resource "aws_launch_template" "green" {
  name_prefix   = "${local.green_name_prefix}-lt-"
  image_id      = var.green_ami_id != "" ? var.green_ami_id : data.aws_ami.jenkins_golden.id
  instance_type = var.instance_type
  
  vpc_security_group_ids = [var.security_group_id]
  
  iam_instance_profile {
    name = var.iam_instance_profile
  }
  
  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume_size
      iops                  = 3000
      throughput            = 125
      encrypted             = true
      delete_on_termination = true
    }
  }
  
  monitoring {
    enabled = true
  }
  
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 1
  }
  
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    efs_file_system_id = var.efs_file_system_id
    aws_region         = var.aws_region
    environment        = var.environment
    deployment_color   = "green"
    log_group_name     = aws_cloudwatch_log_group.deployment_logs.name
    sns_topic_arn      = aws_sns_topic.deployment_notifications.arn
    health_check_url   = var.health_check_url
  }))
  
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name            = "${local.green_name_prefix}-instance"
      DeploymentColor = "green"
      HealthCheck     = "enabled"
    })
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.green_name_prefix}-launch-template"
  })
}

# Blue Auto Scaling Group
resource "aws_autoscaling_group" "blue" {
  name                = "${local.blue_name_prefix}-asg"
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = var.active_deployment == "blue" ? [var.target_group_arn] : []
  health_check_type   = "ELB"
  health_check_grace_period = var.health_check_grace_period
  
  min_size         = var.active_deployment == "blue" ? var.min_size : 0
  max_size         = var.active_deployment == "blue" ? var.max_size : 0
  desired_capacity = var.active_deployment == "blue" ? var.desired_capacity : 0
  
  launch_template {
    id      = aws_launch_template.blue.id
    version = "$Latest"
  }
  
  # Enterprise-grade scaling policies
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances"
  ]
  
  # Termination policies for enterprise workloads
  termination_policies = ["OldestInstance", "Default"]
  
  # Instance refresh for rolling updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 300
    }
  }
  
  tag {
    key                 = "Name"
    value               = "${local.blue_name_prefix}-asg"
    propagate_at_launch = false
  }
  
  tag {
    key                 = "DeploymentColor"
    value               = "blue"
    propagate_at_launch = true
  }
  
  tag {
    key                 = "DeploymentStrategy"
    value               = "blue-green"
    propagate_at_launch = true
  }
  
  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

# Green Auto Scaling Group
resource "aws_autoscaling_group" "green" {
  name                = "${local.green_name_prefix}-asg"
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = var.active_deployment == "green" ? [var.target_group_arn] : []
  health_check_type   = "ELB"
  health_check_grace_period = var.health_check_grace_period
  
  min_size         = var.active_deployment == "green" ? var.min_size : 0
  max_size         = var.active_deployment == "green" ? var.max_size : 0
  desired_capacity = var.active_deployment == "green" ? var.desired_capacity : 0
  
  launch_template {
    id      = aws_launch_template.green.id
    version = "$Latest"
  }
  
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances"
  ]
  
  termination_policies = ["OldestInstance", "Default"]
  
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 300
    }
  }
  
  tag {
    key                 = "Name"
    value               = "${local.green_name_prefix}-asg"
    propagate_at_launch = false
  }
  
  tag {
    key                 = "DeploymentColor"
    value               = "green"
    propagate_at_launch = true
  }
  
  tag {
    key                 = "DeploymentStrategy"
    value               = "blue-green"
    propagate_at_launch = true
  }
  
  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

# CloudWatch Alarms for Blue Environment
resource "aws_cloudwatch_metric_alarm" "blue_high_cpu" {
  alarm_name          = "${local.blue_name_prefix}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors blue environment CPU utilization"
  alarm_actions       = [aws_sns_topic.deployment_notifications.arn]
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.blue.name
  }
  
  tags = local.common_tags
}

# CloudWatch Alarms for Green Environment
resource "aws_cloudwatch_metric_alarm" "green_high_cpu" {
  alarm_name          = "${local.green_name_prefix}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors green environment CPU utilization"
  alarm_actions       = [aws_sns_topic.deployment_notifications.arn]
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.green.name
  }
  
  tags = local.common_tags
}

# Lambda function for automated deployment orchestration
resource "aws_lambda_function" "deployment_orchestrator" {
  filename         = "${path.module}/deployment_orchestrator.zip"
  function_name    = "${var.project_name}-${var.environment}-deployment-orchestrator"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 300
  
  environment {
    variables = {
      BLUE_ASG_NAME    = aws_autoscaling_group.blue.name
      GREEN_ASG_NAME   = aws_autoscaling_group.green.name
      TARGET_GROUP_ARN = var.target_group_arn
      SNS_TOPIC_ARN    = aws_sns_topic.deployment_notifications.arn
      LOG_GROUP_NAME   = aws_cloudwatch_log_group.deployment_logs.name
    }
  }
  
  tags = local.common_tags
}

# IAM Role for Lambda deployment orchestrator
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-${var.environment}-deployment-lambda-role"
  
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
  
  tags = local.common_tags
}

# IAM Policy for Lambda deployment orchestrator
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-${var.environment}-deployment-lambda-policy"
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
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:DescribeAutoScalingGroups",
          "ec2:DescribeInstances",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:DescribeTargetHealth",
          "sns:Publish"
        ]
        Resource = "*"
      }
    ]
  })
}

# EventBridge rule for scheduled health checks
resource "aws_cloudwatch_event_rule" "health_check" {
  name                = "${var.project_name}-${var.environment}-health-check"
  description         = "Trigger health check for blue/green deployment"
  schedule_expression = "rate(5 minutes)"
  
  tags = local.common_tags
}

# EventBridge target for health check
resource "aws_cloudwatch_event_target" "health_check_target" {
  rule      = aws_cloudwatch_event_rule.health_check.name
  target_id = "HealthCheckTarget"
  arn       = aws_lambda_function.deployment_orchestrator.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.deployment_orchestrator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.health_check.arn
}
