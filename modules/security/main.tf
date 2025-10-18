# Security Groups Module - Main Configuration
# Author: Abdihakim Said

# ALB Security Group
resource "aws_security_group" "alb" {
  name_prefix = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-alb-sg"
  vpc_id      = var.vpc_id

  description = "Security group for Jenkins Application Load Balancer"

  # HTTP access from internet
  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Jenkins port from internet
  ingress {
    description = "Jenkins from Internet"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access from internet
  ingress {
    description = "HTTPS from Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-alb-sg"
    Type = "ALB Security Group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Jenkins Security Group
resource "aws_security_group" "jenkins" {
  name_prefix = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-jenkins-sg"
  vpc_id      = var.vpc_id

  description = "Security group for Jenkins instances"

  # Jenkins port from ALB
  ingress {
    description     = "Jenkins from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # SSH access from VPC
  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # JNLP port for Jenkins agents
  ingress {
    description = "JNLP for Jenkins agents"
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-jenkins-sg"
    Type = "Jenkins Security Group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# EFS Security Group
resource "aws_security_group" "efs" {
  name_prefix = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-efs-sg"
  vpc_id      = var.vpc_id

  description = "Security group for EFS file system"

  # NFS access from Jenkins instances
  ingress {
    description     = "NFS from Jenkins"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins.id]
  }

  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-efs-sg"
    Type = "EFS Security Group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# RDS Security Group (for future database needs)
resource "aws_security_group" "rds" {
  name_prefix = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-rds-sg"
  vpc_id      = var.vpc_id

  description = "Security group for RDS database"

  # MySQL/Aurora access from Jenkins instances
  ingress {
    description     = "MySQL from Jenkins"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins.id]
  }

  # PostgreSQL access from Jenkins instances
  ingress {
    description     = "PostgreSQL from Jenkins"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins.id]
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-rds-sg"
    Type = "RDS Security Group"
  })

  lifecycle {
    create_before_destroy = true
  }
}
