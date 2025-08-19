# Jenkins Enterprise Platform - Root Terraform Configuration
# Parent module that orchestrates all child modules
# Version: 2.0
# Date: 2025-08-18

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure AWS Provider
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "DevOps Team"
      Version     = "2.0"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# Local values
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = "DevOps Team"
    Version     = "2.0"
    Epic        = "Epic-2-Golden-Image"
    CreatedBy   = "Learning Environment"
  }
}

# Network Module - Creates VPC, subnets, gateways, route tables
module "network" {
  source = "./modules/network"
  
  environment             = var.environment
  project_name           = var.project_name
  create_vpc             = var.create_vpc
  vpc_name               = var.vpc_name
  vpc_cidr               = var.vpc_cidr
  public_subnet_cidrs    = var.public_subnet_cidrs
  private_subnet_cidrs   = var.private_subnet_cidrs
  availability_zones     = data.aws_availability_zones.available.names
  
  common_tags = local.common_tags
}

# Security Module - Creates security groups, IAM roles, key pairs
module "security" {
  source = "./modules/security"
  
  environment     = var.environment
  project_name   = var.project_name
  vpc_id         = module.network.vpc_id
  vpc_cidr       = module.network.vpc_cidr_block
  public_key     = var.public_key
  
  # Security services
  enable_guardduty      = var.enable_guardduty
  enable_config         = var.enable_config
  enable_cloudtrail     = var.enable_cloudtrail
  enable_security_hub   = var.enable_security_hub
  enable_vpc_flow_logs  = var.enable_vpc_flow_logs
  
  common_tags = local.common_tags
}

# Storage Module - Creates S3 buckets, EFS if enabled
module "storage" {
  source = "./modules/storage"
  
  environment           = var.environment
  project_name         = var.project_name
  vpc_id               = module.network.vpc_id
  private_subnet_ids   = module.network.private_subnet_ids
  security_group_ids   = [module.security.jenkins_instances_security_group_id]
  
  # S3 Configuration
  backup_retention_days = var.backup_retention_days
  
  # EFS Configuration
  enable_efs                  = var.enable_efs
  efs_performance_mode        = var.efs_performance_mode
  efs_throughput_mode        = var.efs_throughput_mode
  efs_provisioned_throughput = var.efs_provisioned_throughput
  efs_encryption_enabled     = var.efs_encryption_enabled
  efs_backup_enabled         = var.efs_backup_enabled
  jenkins_uid                = var.jenkins_uid
  jenkins_gid                = var.jenkins_gid
  
  common_tags = local.common_tags
}

# Compute Module - Creates launch template, ASG, ALB
module "compute" {
  source = "./modules/compute"
  
  environment                = var.environment
  project_name              = var.project_name
  vpc_id                    = module.network.vpc_id
  public_subnet_ids         = module.network.public_subnet_ids
  private_subnet_ids        = module.network.private_subnet_ids
  
  # Security
  alb_security_group_id       = module.security.jenkins_alb_security_group_id
  instances_security_group_id = module.security.jenkins_instances_security_group_id
  instance_profile_name       = module.security.jenkins_instance_profile_name
  key_pair_name              = module.security.jenkins_key_pair_name
  
  # Instance Configuration
  instance_type        = var.instance_type
  golden_ami_id        = var.golden_ami_id
  root_volume_size     = var.root_volume_size
  
  # Auto Scaling Configuration
  asg_min_size         = var.asg_min_size
  asg_max_size         = var.asg_max_size
  asg_desired_capacity = var.asg_desired_capacity
  
  # Application Configuration
  java_version         = var.java_version
  jenkins_version      = var.jenkins_version
  
  # Storage
  s3_backup_bucket     = module.storage.jenkins_backup_bucket_name
  efs_id               = var.enable_efs ? module.storage.efs_id : ""
  
  # Load Balancer
  enable_deletion_protection = var.enable_deletion_protection
  
  common_tags = local.common_tags
}

# Monitoring Module - Creates CloudWatch alarms, dashboards, SNS
module "monitoring" {
  source = "./modules/monitoring"
  
  environment                 = var.environment
  project_name               = var.project_name
  autoscaling_group_name     = module.compute.jenkins_autoscaling_group_name
  load_balancer_arn_suffix   = module.compute.jenkins_alb_arn_suffix
  target_group_arn_suffix    = module.compute.jenkins_target_group_arn_suffix
  
  # Notification Configuration
  notification_email   = var.notification_email
  slack_webhook_url    = var.slack_webhook_url
  log_retention_days   = var.log_retention_days
  
  # EFS Monitoring (if enabled)
  efs_id = var.enable_efs ? module.storage.efs_id : null
  
  common_tags = local.common_tags
}
