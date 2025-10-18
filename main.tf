# Jenkins Enterprise Platform - Main Configuration
# Author: Abdihakim Said
# Epic 2: Golden Image Implementation

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Owner       = var.owner
      CreatedBy   = var.created_by
      ManagedBy   = "Terraform"
      Epic        = "Epic-2-Golden-Image"
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = data.aws_availability_zones.available.names
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  
  tags = local.common_tags
}

# Security Groups Module
module "security_groups" {
  source = "./modules/security"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = var.vpc_cidr
  
  tags = local.common_tags
}

# IAM Module
module "iam" {
  source = "./modules/iam"

  project_name = var.project_name
  environment  = var.environment
  
  tags = local.common_tags
}

# EFS Module
module "efs" {
  source = "./modules/efs"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  security_group_id  = module.security_groups.efs_security_group_id
  
  tags = local.common_tags
}

# ALB Module
module "alb" {
  source = "./modules/alb"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  security_group_id  = module.security_groups.alb_security_group_id
  
  tags = local.common_tags
}

# Jenkins Module
module "jenkins" {
  source = "./modules/jenkins"

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  security_group_id     = module.security_groups.jenkins_security_group_id
  iam_instance_profile  = module.iam.instance_profile_name
  target_group_arn      = module.alb.target_group_arn
  efs_file_system_id    = module.efs.file_system_id
  efs_dns_name          = module.efs.dns_name
  
  # Jenkins specific configuration
  instance_type         = var.jenkins_instance_type
  min_size              = var.jenkins_min_size
  max_size              = var.jenkins_max_size
  desired_capacity      = var.jenkins_desired_capacity
  health_check_grace_period = var.health_check_grace_period
  
  tags = local.common_tags
}

# CloudWatch Module
module "cloudwatch" {
  source = "./modules/cloudwatch"

  project_name    = var.project_name
  environment     = var.environment
  
  tags = local.common_tags
}

# Inspector Module
module "inspector" {
  source = "./modules/inspector"

  project_name = var.project_name
  environment  = var.environment
  
  tags = local.common_tags
}

# Local values
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
    CreatedBy   = var.created_by
    ManagedBy   = "Terraform"
    Epic        = "Epic-2-Golden-Image"
  }
}
