# Enterprise Observability Module - Production Grade
# Prometheus, Grafana, AlertManager with High Availability

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
    Module = "enterprise-observability"
  })
}

# Dedicated VPC Endpoints for Observability
resource "aws_vpc_endpoint" "s3_observability" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-observability-s3-endpoint"
  })
}

# S3 Bucket for Long-term Metrics Storage (Thanos)
resource "aws_s3_bucket" "metrics_storage" {
  bucket = "${var.project_name}-${var.environment}-metrics-storage-${random_id.bucket_suffix.hex}"

  tags = merge(local.common_tags, {
    Name = "Enterprise Metrics Storage"
    Purpose = "Long-term metrics retention"
  })
}

resource "aws_s3_bucket_versioning" "metrics_storage" {
  bucket = aws_s3_bucket.metrics_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "metrics_storage" {
  bucket = aws_s3_bucket.metrics_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "metrics_storage" {
  bucket = aws_s3_bucket.metrics_storage.id

  rule {
    id     = "metrics_lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 2555  # 7 years retention
    }
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# ECS Cluster for Observability Stack
resource "aws_ecs_cluster" "observability" {
  name = "${var.project_name}-${var.environment}-observability"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"
      
      log_configuration {
        cloud_watch_log_group_name = aws_cloudwatch_log_group.ecs_exec.name
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-observability-cluster"
  })
}

resource "aws_ecs_cluster_capacity_providers" "observability" {
  cluster_name = aws_ecs_cluster.observability.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 70
    capacity_provider = "FARGATE"
  }

  default_capacity_provider_strategy {
    base              = 0
    weight            = 30
    capacity_provider = "FARGATE_SPOT"
  }
}

# EFS for Persistent Storage
resource "aws_efs_file_system" "observability" {
  creation_token = "${var.project_name}-${var.environment}-observability"
  encrypted      = true

  performance_mode = "generalPurpose"
  throughput_mode  = "provisioned"
  provisioned_throughput_in_mibps = 200

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-observability-efs"
  })
}

resource "aws_efs_backup_policy" "observability" {
  file_system_id = aws_efs_file_system.observability.id

  backup_policy {
    status = "ENABLED"
  }
}

# EFS Mount Targets
resource "aws_efs_mount_target" "observability" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.observability.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

# EFS Access Points
resource "aws_efs_access_point" "prometheus" {
  file_system_id = aws_efs_file_system.observability.id

  posix_user {
    gid = 65534
    uid = 65534
  }

  root_directory {
    path = "/prometheus"
    creation_info {
      owner_gid   = 65534
      owner_uid   = 65534
      permissions = "755"
    }
  }

  tags = merge(local.common_tags, {
    Name = "prometheus-access-point"
  })
}

resource "aws_efs_access_point" "grafana" {
  file_system_id = aws_efs_file_system.observability.id

  posix_user {
    gid = 472
    uid = 472
  }

  root_directory {
    path = "/grafana"
    creation_info {
      owner_gid   = 472
      owner_uid   = 472
      permissions = "755"
    }
  }

  tags = merge(local.common_tags, {
    Name = "grafana-access-point"
  })
}

resource "aws_efs_access_point" "alertmanager" {
  file_system_id = aws_efs_file_system.observability.id

  posix_user {
    gid = 65534
    uid = 65534
  }

  root_directory {
    path = "/alertmanager"
    creation_info {
      owner_gid   = 65534
      owner_uid   = 65534
      permissions = "755"
    }
  }

  tags = merge(local.common_tags, {
    Name = "alertmanager-access-point"
  })
}

# Security Groups
resource "aws_security_group" "observability" {
  name_prefix = "${var.project_name}-${var.environment}-observability-"
  vpc_id      = var.vpc_id

  # Prometheus
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Prometheus web interface"
  }

  # Grafana
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Grafana web interface"
  }

  # AlertManager
  ingress {
    from_port   = 9093
    to_port     = 9093
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "AlertManager web interface"
  }

  # Node Exporter
  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Node Exporter metrics"
  }

  # Thanos Sidecar
  ingress {
    from_port   = 10901
    to_port     = 10901
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Thanos Sidecar gRPC"
  }

  # Thanos Query
  ingress {
    from_port   = 10902
    to_port     = 10902
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Thanos Query HTTP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-observability-sg"
  })
}

resource "aws_security_group" "efs" {
  name_prefix = "${var.project_name}-${var.environment}-observability-efs-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.observability.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-observability-efs-sg"
  })
}

# IAM Roles
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-${var.environment}-observability-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-${var.environment}-observability-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "ecs_task" {
  name = "${var.project_name}-${var.environment}-observability-task-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "autoscaling:DescribeAutoScalingGroups",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeTargetGroups",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:*"
        ]
        Resource = [
          aws_s3_bucket.metrics_storage.arn,
          "${aws_s3_bucket.metrics_storage.arn}/*"
        ]
      }
    ]
  })
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "prometheus" {
  name              = "/ecs/${var.project_name}/${var.environment}/prometheus"
  retention_in_days = 30

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "grafana" {
  name              = "/ecs/${var.project_name}/${var.environment}/grafana"
  retention_in_days = 30

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "alertmanager" {
  name              = "/ecs/${var.project_name}/${var.environment}/alertmanager"
  retention_in_days = 30

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "thanos" {
  name              = "/ecs/${var.project_name}/${var.environment}/thanos"
  retention_in_days = 30

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "ecs_exec" {
  name              = "/ecs/${var.project_name}/${var.environment}/exec"
  retention_in_days = 7

  tags = local.common_tags
}

# Application Load Balancer for Observability
resource "aws_lb" "observability" {
  name               = "jenkins-${var.environment}-obs"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "observability-alb"
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-observability-alb"
  })
}

resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-${var.environment}-obs-alb-"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-observability-alb-sg"
  })
}

# S3 Bucket for ALB Logs
resource "aws_s3_bucket" "alb_logs" {
  bucket = "${var.project_name}-${var.environment}-obs-alb-logs-${random_id.bucket_suffix.hex}"

  tags = merge(local.common_tags, {
    Name = "Observability ALB Logs"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "alb_logs_lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 90
    }
  }
}

# Data source
data "aws_region" "current" {}

data "aws_elb_service_account" "main" {}
