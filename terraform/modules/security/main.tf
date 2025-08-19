# Security Module - Jenkins Enterprise Platform
# Creates security groups, IAM roles, key pairs, and security services
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
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Security Group for Application Load Balancer
resource "aws_security_group" "jenkins_alb" {
  name_prefix = "${var.environment}-${var.project_name}-alb-"
  vpc_id      = var.vpc_id
  description = "Security group for Jenkins Application Load Balancer"
  
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-alb-sg"
    Type = "ALB Security Group"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Security Group for Jenkins Instances
resource "aws_security_group" "jenkins_instances" {
  name_prefix = "${var.environment}-${var.project_name}-instances-"
  vpc_id      = var.vpc_id
  description = "Security group for Jenkins instances"
  
  ingress {
    description     = "Jenkins from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins_alb.id]
  }
  
  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  
  ingress {
    description = "Node Exporter from VPC"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-instances-sg"
    Type = "Jenkins Instances Security Group"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# IAM Role for Jenkins instances
resource "aws_iam_role" "jenkins_instance_role" {
  name = "${var.environment}-${var.project_name}-jenkins-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-jenkins-role"
    Type = "Jenkins Instance Role"
  })
}

# IAM Policy for Jenkins instances
resource "aws_iam_role_policy" "jenkins_instance_policy" {
  name = "${var.environment}-${var.project_name}-jenkins-policy"
  role = aws_iam_role.jenkins_instance_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.environment}-${var.project_name}-backup-*",
          "arn:aws:s3:::${var.environment}-${var.project_name}-backup-*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ssm:PutParameter"
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:DescribeSnapshots",
          "ec2:DescribeVolumes",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeLaunchTemplates"
        ]
        Resource = "*"
      }
    ]
  })
}

# Additional IAM policy for EFS access (if EFS is enabled)
resource "aws_iam_role_policy" "jenkins_efs_policy" {
  count = var.enable_efs_access ? 1 : 0
  
  name = "${var.environment}-${var.project_name}-jenkins-efs-policy"
  role = aws_iam_role.jenkins_instance_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets",
          "elasticfilesystem:DescribeAccessPoints"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "${var.environment}-${var.project_name}-jenkins-profile"
  role = aws_iam_role.jenkins_instance_role.name
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-jenkins-profile"
    Type = "Jenkins Instance Profile"
  })
}

# Key Pair for EC2 instances
resource "aws_key_pair" "jenkins_key" {
  key_name   = "${var.environment}-${var.project_name}-key"
  public_key = var.public_key
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-key"
    Type = "Jenkins Key Pair"
  })
}

# GuardDuty Detector
resource "aws_guardduty_detector" "main" {
  count = var.enable_guardduty ? 1 : 0
  
  enable = true
  
  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-guardduty"
    Type = "GuardDuty Detector"
  })
}

# Config Configuration Recorder
resource "aws_config_configuration_recorder" "main" {
  count = var.enable_config ? 1 : 0
  
  name     = "${var.environment}-${var.project_name}-config-recorder"
  role_arn = aws_iam_role.config_role[0].arn
  
  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
  
  depends_on = [aws_config_delivery_channel.main]
}

# Config Delivery Channel
resource "aws_config_delivery_channel" "main" {
  count = var.enable_config ? 1 : 0
  
  name           = "${var.environment}-${var.project_name}-config-delivery-channel"
  s3_bucket_name = aws_s3_bucket.config_bucket[0].bucket
  
  depends_on = [aws_s3_bucket_policy.config_bucket_policy]
}

# S3 Bucket for Config
resource "aws_s3_bucket" "config_bucket" {
  count = var.enable_config ? 1 : 0
  
  bucket        = "${var.environment}-${var.project_name}-config-${random_id.config_bucket_suffix[0].hex}"
  force_destroy = true
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-config-bucket"
    Type = "Config Bucket"
  })
}

resource "random_id" "config_bucket_suffix" {
  count = var.enable_config ? 1 : 0
  
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "config_bucket" {
  count = var.enable_config ? 1 : 0
  
  bucket = aws_s3_bucket.config_bucket[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_encryption" "config_bucket" {
  count = var.enable_config ? 1 : 0
  
  bucket = aws_s3_bucket.config_bucket[0].id
  
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

# S3 Bucket Policy for Config
resource "aws_s3_bucket_policy" "config_bucket_policy" {
  count = var.enable_config ? 1 : 0
  
  bucket = aws_s3_bucket.config_bucket[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config_bucket[0].arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketExistenceCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.config_bucket[0].arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config_bucket[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# IAM Role for Config
resource "aws_iam_role" "config_role" {
  count = var.enable_config ? 1 : 0
  
  name = "${var.environment}-${var.project_name}-config-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-config-role"
    Type = "Config Service Role"
  })
}

# IAM Role Policy Attachment for Config
resource "aws_iam_role_policy_attachment" "config_role_policy" {
  count = var.enable_config ? 1 : 0
  
  role       = aws_iam_role.config_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/ConfigRole"
}

# CloudTrail
resource "aws_cloudtrail" "main" {
  count = var.enable_cloudtrail ? 1 : 0
  
  name           = "${var.environment}-${var.project_name}-cloudtrail"
  s3_bucket_name = aws_s3_bucket.cloudtrail_bucket[0].bucket
  
  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    exclude_management_event_sources = []
    
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::*/*"]
    }
  }
  
  depends_on = [aws_s3_bucket_policy.cloudtrail_bucket_policy]
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-cloudtrail"
    Type = "CloudTrail"
  })
}

# S3 Bucket for CloudTrail
resource "aws_s3_bucket" "cloudtrail_bucket" {
  count = var.enable_cloudtrail ? 1 : 0
  
  bucket        = "${var.environment}-${var.project_name}-cloudtrail-${random_id.cloudtrail_bucket_suffix[0].hex}"
  force_destroy = true
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-cloudtrail-bucket"
    Type = "CloudTrail Bucket"
  })
}

resource "random_id" "cloudtrail_bucket_suffix" {
  count = var.enable_cloudtrail ? 1 : 0
  
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "cloudtrail_bucket" {
  count = var.enable_cloudtrail ? 1 : 0
  
  bucket = aws_s3_bucket.cloudtrail_bucket[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_encryption" "cloudtrail_bucket" {
  count = var.enable_cloudtrail ? 1 : 0
  
  bucket = aws_s3_bucket.cloudtrail_bucket[0].id
  
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

# S3 Bucket Policy for CloudTrail
resource "aws_s3_bucket_policy" "cloudtrail_bucket_policy" {
  count = var.enable_cloudtrail ? 1 : 0
  
  bucket = aws_s3_bucket.cloudtrail_bucket[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_bucket[0].arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.environment}-${var.project_name}-cloudtrail"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_bucket[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.environment}-${var.project_name}-cloudtrail"
          }
        }
      }
    ]
  })
}

# VPC Flow Logs
resource "aws_flow_log" "vpc_flow_log" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  
  iam_role_arn    = aws_iam_role.flow_log_role[0].arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log[0].arn
  traffic_type    = "ALL"
  vpc_id          = var.vpc_id
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-vpc-flow-log"
    Type = "VPC Flow Log"
  })
}

# CloudWatch Log Group for VPC Flow Logs
resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  
  name              = "/aws/vpc/flowlogs/${var.environment}-${var.project_name}"
  retention_in_days = 30
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-vpc-flow-log-group"
    Type = "VPC Flow Log Group"
  })
}

# IAM Role for VPC Flow Logs
resource "aws_iam_role" "flow_log_role" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  
  name = "${var.environment}-${var.project_name}-flow-log-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-flow-log-role"
    Type = "VPC Flow Log Role"
  })
}

# IAM Role Policy for VPC Flow Logs
resource "aws_iam_role_policy" "flow_log_policy" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  
  name = "${var.environment}-${var.project_name}-flow-log-policy"
  role = aws_iam_role.flow_log_role[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}
