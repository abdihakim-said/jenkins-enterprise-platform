# Blue/Green Deployment Module for Jenkins Enterprise Platform
# Epic 5: Story 6.1 - Blue/Green deployment strategy

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Local variables
locals {
  common_tags = merge(var.common_tags, {
    Module      = "blue-green-deployment"
    Environment = var.environment
    Project     = var.project_name
  })
  
  # Determine active and inactive environments
  active_color   = var.active_deployment
  inactive_color = var.active_deployment == "blue" ? "green" : "blue"
  
  # Launch template names
  blue_lt_name  = "${var.project_name}-${var.environment}-blue-lt"
  green_lt_name = "${var.project_name}-${var.environment}-green-lt"
  
  # Auto Scaling Group names
  blue_asg_name  = "${var.project_name}-${var.environment}-blue-asg"
  green_asg_name = "${var.project_name}-${var.environment}-green-asg"
}

# Data sources
data "aws_ami" "jenkins_golden" {
  most_recent = true
  owners      = ["self"]
  
  filter {
    name   = "name"
    values = ["jenkins-golden-ami-${var.environment}-*"]
  }
  
  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  
  filter {
    name   = "tag:Type"
    values = ["private"]
  }
}

# Blue Launch Template
resource "aws_launch_template" "blue" {
  name_prefix   = "${local.blue_lt_name}-"
  image_id      = var.blue_ami_id != "" ? var.blue_ami_id : data.aws_ami.jenkins_golden.id
  instance_type = var.instance_type
  key_name      = var.key_name
  
  vpc_security_group_ids = var.security_group_ids
  
  iam_instance_profile {
    name = var.instance_profile_name
  }
  
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume_size
      iops                  = 3000
      throughput            = 125
      encrypted             = true
      delete_on_termination = true
    }
  }
  
  user_data = base64encode(templatefile("${path.module}/templates/user-data.sh", {
    environment        = var.environment
    efs_file_system_id = var.efs_file_system_id
    deployment_color   = "blue"
    jenkins_version    = var.jenkins_version
    aws_region         = var.aws_region
  }))
  
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name            = "${var.project_name}-${var.environment}-blue"
      DeploymentColor = "blue"
      LaunchTemplate  = local.blue_lt_name
    })
  }
  
  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name            = "${var.project_name}-${var.environment}-blue-volume"
      DeploymentColor = "blue"
    })
  }
  
  tags = merge(local.common_tags, {
    Name            = local.blue_lt_name
    DeploymentColor = "blue"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Green Launch Template
resource "aws_launch_template" "green" {
  name_prefix   = "${local.green_lt_name}-"
  image_id      = var.green_ami_id != "" ? var.green_ami_id : data.aws_ami.jenkins_golden.id
  instance_type = var.instance_type
  key_name      = var.key_name
  
  vpc_security_group_ids = var.security_group_ids
  
  iam_instance_profile {
    name = var.instance_profile_name
  }
  
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume_size
      iops                  = 3000
      throughput            = 125
      encrypted             = true
      delete_on_termination = true
    }
  }
  
  user_data = base64encode(templatefile("${path.module}/templates/user-data.sh", {
    environment        = var.environment
    efs_file_system_id = var.efs_file_system_id
    deployment_color   = "green"
    jenkins_version    = var.jenkins_version
    aws_region         = var.aws_region
  }))
  
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name            = "${var.project_name}-${var.environment}-green"
      DeploymentColor = "green"
      LaunchTemplate  = local.green_lt_name
    })
  }
  
  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name            = "${var.project_name}-${var.environment}-green-volume"
      DeploymentColor = "green"
    })
  }
  
  tags = merge(local.common_tags, {
    Name            = local.green_lt_name
    DeploymentColor = "green"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Blue Auto Scaling Group
resource "aws_autoscaling_group" "blue" {
  name                = local.blue_asg_name
  vpc_zone_identifier = data.aws_subnets.private.ids
  target_group_arns   = local.active_color == "blue" ? var.target_group_arns : []
  health_check_type   = "ELB"
  health_check_grace_period = var.health_check_grace_period
  
  min_size         = local.active_color == "blue" ? var.min_size : 0
  max_size         = local.active_color == "blue" ? var.max_size : 0
  desired_capacity = local.active_color == "blue" ? var.desired_capacity : 0
  
  launch_template {
    id      = aws_launch_template.blue.id
    version = "$Latest"
  }
  
  # Instance refresh configuration
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup       = var.instance_warmup_time
    }
    triggers = ["tag"]
  }
  
  # Lifecycle hooks
  initial_lifecycle_hook {
    name                 = "blue-launching-hook"
    default_result       = "ABANDON"
    heartbeat_timeout    = 900
    lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
    
    notification_metadata = jsonencode({
      deployment_color = "blue"
      environment     = var.environment
    })
  }
  
  initial_lifecycle_hook {
    name                 = "blue-terminating-hook"
    default_result       = "CONTINUE"
    heartbeat_timeout    = 300
    lifecycle_transition = "autoscaling:EC2_INSTANCE_TERMINATING"
    
    notification_metadata = jsonencode({
      deployment_color = "blue"
      environment     = var.environment
    })
  }
  
  tag {
    key                 = "Name"
    value               = local.blue_asg_name
    propagate_at_launch = false
  }
  
  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
  
  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }
  
  tag {
    key                 = "DeploymentColor"
    value               = "blue"
    propagate_at_launch = true
  }
  
  tag {
    key                 = "ActiveDeployment"
    value               = local.active_color == "blue" ? "true" : "false"
    propagate_at_launch = true
  }
  
  lifecycle {
    create_before_destroy = true
    ignore_changes       = [desired_capacity]
  }
}

# Green Auto Scaling Group
resource "aws_autoscaling_group" "green" {
  name                = local.green_asg_name
  vpc_zone_identifier = data.aws_subnets.private.ids
  target_group_arns   = local.active_color == "green" ? var.target_group_arns : []
  health_check_type   = "ELB"
  health_check_grace_period = var.health_check_grace_period
  
  min_size         = local.active_color == "green" ? var.min_size : 0
  max_size         = local.active_color == "green" ? var.max_size : 0
  desired_capacity = local.active_color == "green" ? var.desired_capacity : 0
  
  launch_template {
    id      = aws_launch_template.green.id
    version = "$Latest"
  }
  
  # Instance refresh configuration
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup       = var.instance_warmup_time
    }
    triggers = ["tag"]
  }
  
  # Lifecycle hooks
  initial_lifecycle_hook {
    name                 = "green-launching-hook"
    default_result       = "ABANDON"
    heartbeat_timeout    = 900
    lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
    
    notification_metadata = jsonencode({
      deployment_color = "green"
      environment     = var.environment
    })
  }
  
  initial_lifecycle_hook {
    name                 = "green-terminating-hook"
    default_result       = "CONTINUE"
    heartbeat_timeout    = 300
    lifecycle_transition = "autoscaling:EC2_INSTANCE_TERMINATING"
    
    notification_metadata = jsonencode({
      deployment_color = "green"
      environment     = var.environment
    })
  }
  
  tag {
    key                 = "Name"
    value               = local.green_asg_name
    propagate_at_launch = false
  }
  
  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
  
  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }
  
  tag {
    key                 = "DeploymentColor"
    value               = "green"
    propagate_at_launch = true
  }
  
  tag {
    key                 = "ActiveDeployment"
    value               = local.active_color == "green" ? "true" : "false"
    propagate_at_launch = true
  }
  
  lifecycle {
    create_before_destroy = true
    ignore_changes       = [desired_capacity]
  }
}

# CloudWatch Alarms for Blue Deployment
resource "aws_cloudwatch_metric_alarm" "blue_high_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-blue-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization for blue deployment"
  alarm_actions       = var.alarm_actions
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.blue.name
  }
  
  tags = merge(local.common_tags, {
    Name            = "${var.project_name}-${var.environment}-blue-high-cpu"
    DeploymentColor = "blue"
  })
}

# CloudWatch Alarms for Green Deployment
resource "aws_cloudwatch_metric_alarm" "green_high_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-green-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization for green deployment"
  alarm_actions       = var.alarm_actions
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.green.name
  }
  
  tags = merge(local.common_tags, {
    Name            = "${var.project_name}-${var.environment}-green-high-cpu"
    DeploymentColor = "green"
  })
}

# Auto Scaling Policies for Blue
resource "aws_autoscaling_policy" "blue_scale_up" {
  name                   = "${var.project_name}-${var.environment}-blue-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.blue.name
}

resource "aws_autoscaling_policy" "blue_scale_down" {
  name                   = "${var.project_name}-${var.environment}-blue-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.blue.name
}

# Auto Scaling Policies for Green
resource "aws_autoscaling_policy" "green_scale_up" {
  name                   = "${var.project_name}-${var.environment}-green-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.green.name
}

resource "aws_autoscaling_policy" "green_scale_down" {
  name                   = "${var.project_name}-${var.environment}-green-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.green.name
}

# CloudWatch Alarms for Auto Scaling - Blue
resource "aws_cloudwatch_metric_alarm" "blue_cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-blue-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.blue_scale_up.arn]
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.blue.name
  }
}

resource "aws_cloudwatch_metric_alarm" "blue_cpu_low" {
  alarm_name          = "${var.project_name}-${var.environment}-blue-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "30"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.blue_scale_down.arn]
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.blue.name
  }
}

# CloudWatch Alarms for Auto Scaling - Green
resource "aws_cloudwatch_metric_alarm" "green_cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-green-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.green_scale_up.arn]
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.green.name
  }
}

resource "aws_cloudwatch_metric_alarm" "green_cpu_low" {
  alarm_name          = "${var.project_name}-${var.environment}-green-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "30"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.green_scale_down.arn]
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.green.name
  }
}
