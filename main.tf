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
  kms_key_id           = module.iam.kms_key_id
  kms_key_arn          = module.iam.kms_key_arn

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

  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  security_group_id = module.security_groups.alb_security_group_id
  kms_key_id        = module.iam.kms_key_id

  tags = local.common_tags
}

# CloudWatch Module
module "cloudwatch" {
  source = "./modules/cloudwatch"

  project_name = var.project_name
  environment  = var.environment
  kms_key_id   = module.iam.kms_key_id
  kms_key_arn  = module.iam.kms_key_arn

  tags = local.common_tags
}

# Inspector Module
module "inspector" {
  source = "./modules/inspector"

  project_name = var.project_name
  environment  = var.environment
  kms_key_id   = module.iam.kms_key_id

  tags = local.common_tags
}

# Blue/Green Deployment Module
module "blue_green_deployment" {
  source = "./modules/blue-green-deployment"

  project_name         = var.project_name
  environment          = var.environment
  vpc_id               = module.vpc.vpc_id
  private_subnet_ids   = module.vpc.private_subnet_ids
  security_group_id    = module.security_groups.jenkins_security_group_id
  iam_instance_profile = module.iam.instance_profile_name
  target_group_arn     = module.alb.target_group_arn
  efs_file_system_id   = module.efs.file_system_id
  aws_region           = var.aws_region
  kms_key_id           = module.iam.kms_key_id
  kms_key_arn          = module.iam.kms_key_arn

  # Blue/Green specific configuration
  instance_type = var.jenkins_instance_type

  common_tags = local.common_tags
}

# Cost-Optimized Observability Module
# Smart monitoring using existing infrastructure - saves $105/month vs ECS
module "cost_optimized_observability" {
  source = "./modules/cost-optimized-observability"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
  alert_email  = var.alert_email

  depends_on = [
    module.blue_green_deployment,
    module.alb
  ]
}

# Cost Optimization Module
# Automated scaling, budgets, and cost analytics
module "cost_optimization" {
  source = "./modules/cost-optimization"

  environment          = var.environment
  jenkins_asg_name     = module.blue_green_deployment.blue_asg_name
  jenkins_url          = "https://${module.alb.dns_name}"
  cost_alert_email     = var.alert_email
  monthly_budget_limit = "200"

  common_tags = local.common_tags

  depends_on = [
    module.blue_green_deployment
  ]
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
