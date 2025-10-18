# Launch Template
resource "aws_launch_template" "jenkins" {
  name_prefix   = "${var.environment}-jenkins-${var.color}-"
  image_id      = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [var.jenkins_security_group_id]

  iam_instance_profile {
    name = var.iam_instance_profile
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    efs_id = var.efs_id
    s3_backup_bucket = var.s3_backup_bucket
    environment = var.environment
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.common_tags, {
      Name = "${var.environment}-jenkins-${var.color}"
      Color = var.color
      Role = "jenkins-master"
    })
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-jenkins-${var.color}-lt"
  })
}

# Auto Scaling Group
resource "aws_autoscaling_group" "jenkins" {
  name                = "${var.environment}-jenkins-asg-${var.color}"
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [var.target_group_arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  launch_template {
    id      = aws_launch_template.jenkins.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.environment}-jenkins-asg-${var.color}"
    propagate_at_launch = false
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Color"
    value               = var.color
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "jenkins-master"
    propagate_at_launch = true
  }
}

# Data source for Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
