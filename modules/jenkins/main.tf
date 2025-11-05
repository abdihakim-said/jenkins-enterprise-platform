# Jenkins Module - Main Configuration
# Author: Abdihakim Said

# Data sources
data "aws_ami" "jenkins_golden" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["jenkins-golden-ami-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_region" "current" {}

# Get SSH public key from Systems Manager
data "aws_ssm_parameter" "jenkins_public_key" {
  name = "/jenkins/ssh-public-key"
}

# Key Pair
resource "aws_key_pair" "jenkins" {
  key_name   = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-key"
  public_key = data.aws_ssm_parameter.jenkins_public_key.value

  tags = merge(var.tags, {
    Name = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-key"
    Type = "Jenkins Key Pair"
  })
}

# Launch Template
resource "aws_launch_template" "jenkins" {
  name_prefix   = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-lt"
  image_id      = data.aws_ami.jenkins_golden.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.jenkins.key_name

  vpc_security_group_ids = [var.security_group_id]

  iam_instance_profile {
    name = var.iam_instance_profile
  }

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = 50
      volume_type           = "gp3"
      iops                  = 3000
      throughput            = 125
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    efs_file_system_id = var.efs_file_system_id
    aws_region         = data.aws_region.current.name
    environment        = var.environment
    jenkins_version    = var.jenkins_version
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-instance"
      Type = "Jenkins Master"
    })
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-lt"
    Type = "Jenkins Launch Template"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "jenkins" {
  name                = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-asg"
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [var.target_group_arn]
  health_check_type   = "ELB"
  health_check_grace_period = var.health_check_grace_period

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  launch_template {
    id      = aws_launch_template.jenkins.id
    version = "$Latest"
  }

  # Instance refresh configuration
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 300
    }
  }

  # Termination policies
  termination_policies = ["OldestInstance"]

  # Tags
  dynamic "tag" {
    for_each = merge(var.tags, {
      Name = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-asg"
      Type = "Jenkins Auto Scaling Group"
    })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes       = [desired_capacity]
  }
}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.jenkins.name

  policy_type = "SimpleScaling"
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.jenkins.name

  policy_type = "SimpleScaling"
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.jenkins.name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-low-cpu"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "10"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.jenkins.name
  }

  tags = var.tags
}
