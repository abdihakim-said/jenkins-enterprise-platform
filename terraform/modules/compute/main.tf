# Compute Module - Jenkins Enterprise Platform
# Creates Application Load Balancer, Auto Scaling Group, and Launch Template
# Based on deployed infrastructure
# Version: 2.0

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Data sources
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Application Load Balancer
resource "aws_lb" "jenkins_alb" {
  name               = "${var.environment}-jenkins-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids
  
  enable_deletion_protection = var.enable_deletion_protection
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-jenkins-alb"
    Type = "Jenkins ALB"
  })
}

# Target Group for Jenkins
resource "aws_lb_target_group" "jenkins_tg" {
  name     = "${var.environment}-jenkins-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/login"
    matcher             = "200,403"
    port                = "traffic-port"
    protocol            = "HTTP"
  }
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-jenkins-tg"
    Type = "Jenkins Target Group"
  })
}

# ALB Listener
resource "aws_lb_listener" "jenkins_listener" {
  load_balancer_arn = aws_lb.jenkins_alb.arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins_tg.arn
  }
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-jenkins-listener"
    Type = "Jenkins ALB Listener"
  })
}

# Launch Template
resource "aws_launch_template" "jenkins_lt" {
  name_prefix   = "${var.environment}-${var.project_name}-lt"
  image_id      = var.golden_ami_id != "" ? var.golden_ami_id : data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_pair_name
  
  vpc_security_group_ids = [var.instances_security_group_id]
  
  iam_instance_profile {
    name = var.instance_profile_name
  }
  
  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume_size
      iops                  = 3000
      throughput            = 125
      delete_on_termination = true
      encrypted             = true
    }
  }
  
  monitoring {
    enabled = true
  }
  
  user_data = base64encode(templatefile("${path.module}/../../../scripts/user-data.sh", {
    environment     = var.environment
    project_name    = var.project_name
    s3_bucket       = var.s3_backup_bucket
    efs_id          = var.efs_id
    java_version    = var.java_version
    jenkins_version = var.jenkins_version
  }))
  
  tag_specifications {
    resource_type = "instance"
    tags = merge(var.common_tags, {
      Name = "${var.environment}-${var.project_name}-instance"
      Type = "Jenkins Master"
    })
  }
  
  tag_specifications {
    resource_type = "volume"
    tags = merge(var.common_tags, {
      Name = "${var.environment}-${var.project_name}-volume"
      Type = "Jenkins Volume"
    })
  }
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-lt"
    Type = "Jenkins Launch Template"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "jenkins_asg" {
  name                = "${var.environment}-${var.project_name}-asg"
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [aws_lb_target_group.jenkins_tg.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 1200  # 20 minutes for Jenkins startup
  
  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity
  
  launch_template {
    id      = aws_launch_template.jenkins_lt.id
    version = "$Latest"
  }
  
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup       = 300
    }
  }
  
  # Termination policies
  termination_policies = ["OldestInstance"]
  
  tag {
    key                 = "Name"
    value               = "${var.environment}-${var.project_name}-asg"
    propagate_at_launch = false
  }
  
  tag {
    key                 = "Type"
    value               = "Jenkins Auto Scaling Group"
    propagate_at_launch = false
  }
  
  dynamic "tag" {
    for_each = var.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "jenkins_scale_up" {
  name                   = "${var.environment}-${var.project_name}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.jenkins_asg.name
}

resource "aws_autoscaling_policy" "jenkins_scale_down" {
  name                   = "${var.environment}-${var.project_name}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.jenkins_asg.name
}

# CloudWatch Alarms for Auto Scaling
resource "aws_cloudwatch_metric_alarm" "jenkins_cpu_high" {
  alarm_name          = "${var.environment}-jenkins-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors jenkins instance cpu utilization for scaling up"
  alarm_actions       = [aws_autoscaling_policy.jenkins_scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.jenkins_asg.name
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-jenkins-cpu-high-alarm"
    Type = "Auto Scaling Alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "jenkins_cpu_low" {
  alarm_name          = "${var.environment}-jenkins-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "20"
  alarm_description   = "This metric monitors jenkins instance cpu utilization for scaling down"
  alarm_actions       = [aws_autoscaling_policy.jenkins_scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.jenkins_asg.name
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-jenkins-cpu-low-alarm"
    Type = "Auto Scaling Alarm"
  })
}
