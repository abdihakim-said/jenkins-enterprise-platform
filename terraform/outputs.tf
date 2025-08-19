# Jenkins Enterprise Platform - Root Terraform Outputs
# Comprehensive outputs from all child modules
# Version: 2.0
# Date: 2025-08-18

# Network Module Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.network.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.network.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.network.private_subnet_ids
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = module.network.internet_gateway_id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways"
  value       = module.network.nat_gateway_ids
}

# Security Module Outputs
output "jenkins_alb_security_group_id" {
  description = "ID of the Jenkins ALB security group"
  value       = module.security.jenkins_alb_security_group_id
}

output "jenkins_instances_security_group_id" {
  description = "ID of the Jenkins instances security group"
  value       = module.security.jenkins_instances_security_group_id
}

output "jenkins_instance_role_arn" {
  description = "ARN of the Jenkins instance IAM role"
  value       = module.security.jenkins_instance_role_arn
}

output "jenkins_instance_profile_name" {
  description = "Name of the Jenkins instance profile"
  value       = module.security.jenkins_instance_profile_name
}

output "jenkins_key_pair_name" {
  description = "Name of the Jenkins key pair"
  value       = module.security.jenkins_key_pair_name
}

# Storage Module Outputs
output "jenkins_backup_bucket_name" {
  description = "Name of the Jenkins backup S3 bucket"
  value       = module.storage.jenkins_backup_bucket_name
}

output "jenkins_backup_bucket_arn" {
  description = "ARN of the Jenkins backup S3 bucket"
  value       = module.storage.jenkins_backup_bucket_arn
}

output "efs_id" {
  description = "ID of the EFS file system"
  value       = module.storage.efs_id
}

output "efs_dns_name" {
  description = "DNS name of the EFS file system"
  value       = module.storage.efs_dns_name
}

output "jenkins_home_access_point_id" {
  description = "ID of the Jenkins home EFS access point"
  value       = module.storage.jenkins_home_access_point_id
}

# Compute Module Outputs
output "jenkins_alb_arn" {
  description = "ARN of the Jenkins Application Load Balancer"
  value       = module.compute.jenkins_alb_arn
}

output "jenkins_alb_dns_name" {
  description = "DNS name of the Jenkins Application Load Balancer"
  value       = module.compute.jenkins_alb_dns_name
}

output "jenkins_alb_url" {
  description = "URL of the Jenkins Application Load Balancer"
  value       = module.compute.jenkins_alb_url
}

output "jenkins_target_group_arn" {
  description = "ARN of the Jenkins target group"
  value       = module.compute.jenkins_target_group_arn
}

output "jenkins_launch_template_id" {
  description = "ID of the Jenkins launch template"
  value       = module.compute.jenkins_launch_template_id
}

output "jenkins_autoscaling_group_name" {
  description = "Name of the Jenkins Auto Scaling Group"
  value       = module.compute.jenkins_autoscaling_group_name
}

output "golden_ami_id" {
  description = "ID of the Golden AMI used for Jenkins instances"
  value       = module.compute.golden_ami_id
}

# Monitoring Module Outputs
output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = module.monitoring.cloudwatch_dashboard_url
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = module.monitoring.sns_topic_arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = module.monitoring.cloudwatch_log_group_name
}

# Security Services Outputs
output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector"
  value       = module.security.guardduty_detector_id
}

output "config_configuration_recorder_name" {
  description = "Name of the Config configuration recorder"
  value       = module.security.config_configuration_recorder_name
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail"
  value       = module.security.cloudtrail_arn
}

# Environment Information
output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# Module Summaries
output "network_summary" {
  description = "Summary of network resources"
  value       = module.network.network_summary
}

output "security_summary" {
  description = "Summary of security resources"
  value       = module.security.security_summary
}

output "storage_summary" {
  description = "Summary of storage resources"
  value       = module.storage.storage_summary
}

output "compute_summary" {
  description = "Summary of compute resources"
  value       = module.compute.compute_summary
}

# Comprehensive Configuration Summary
output "jenkins_platform_summary" {
  description = "Comprehensive summary of the Jenkins Enterprise Platform"
  value = {
    # Environment
    environment           = var.environment
    project_name         = var.project_name
    aws_region           = var.aws_region
    aws_account_id       = data.aws_caller_identity.current.account_id
    
    # Network
    vpc_id               = module.network.vpc_id
    vpc_cidr             = module.network.vpc_cidr_block
    public_subnets_count = length(module.network.public_subnet_ids)
    private_subnets_count = length(module.network.private_subnet_ids)
    
    # Compute
    jenkins_url          = module.compute.jenkins_alb_url
    instance_type        = var.instance_type
    golden_ami_id        = module.compute.golden_ami_id
    java_version         = var.java_version
    jenkins_version      = var.jenkins_version
    asg_min_size         = var.asg_min_size
    asg_max_size         = var.asg_max_size
    asg_desired_capacity = var.asg_desired_capacity
    
    # Storage
    efs_enabled          = var.enable_efs
    backup_bucket        = module.storage.jenkins_backup_bucket_name
    
    # Security
    security_groups      = 2
    iam_roles           = 1
    guardduty_enabled   = var.enable_guardduty
    config_enabled      = var.enable_config
    cloudtrail_enabled  = var.enable_cloudtrail
    
    # Monitoring
    monitoring_enabled   = true
    dashboard_url       = module.monitoring.cloudwatch_dashboard_url
  }
}

# Deployment Information
output "deployment_info" {
  description = "Deployment information and next steps"
  value = {
    jenkins_url           = module.compute.jenkins_alb_url
    ssh_command          = "ssh -i ~/.ssh/${module.security.jenkins_key_pair_name}.pem ubuntu@<instance-ip>"
    backup_bucket        = module.storage.jenkins_backup_bucket_name
    monitoring_dashboard = module.monitoring.cloudwatch_dashboard_url
    efs_mount_command    = var.enable_efs ? "sudo mount -t efs ${module.storage.efs_id}:/ /mnt/efs" : "EFS not enabled"
    
    next_steps = [
      "1. Access Jenkins at: ${module.compute.jenkins_alb_url}",
      "2. Check CloudWatch dashboard: ${module.monitoring.cloudwatch_dashboard_url}",
      "3. Verify EFS mount if enabled: ${var.enable_efs ? module.storage.efs_id : "N/A"}",
      "4. Configure Jenkins security settings",
      "5. Set up backup schedules and test recovery",
      "6. Review security configurations and compliance"
    ]
  }
}

# Resource Counts
output "resource_counts" {
  description = "Count of resources created by each module"
  value = {
    # Network Resources
    vpc_created              = var.create_vpc ? 1 : 0
    public_subnets          = length(module.network.public_subnet_ids)
    private_subnets         = length(module.network.private_subnet_ids)
    nat_gateways            = length(module.network.nat_gateway_ids)
    
    # Security Resources
    security_groups         = 2 + (var.enable_efs ? 1 : 0)
    iam_roles              = 1 + (var.enable_config ? 1 : 0) + (var.enable_vpc_flow_logs ? 1 : 0)
    key_pairs              = 1
    
    # Storage Resources
    s3_buckets             = 1 + (var.enable_config ? 1 : 0) + (var.enable_cloudtrail ? 1 : 0)
    efs_file_systems       = var.enable_efs ? 1 : 0
    efs_access_points      = var.enable_efs ? 2 : 0
    
    # Compute Resources
    load_balancers         = 1
    target_groups          = 1
    launch_templates       = 1
    autoscaling_groups     = 1
    
    # Monitoring Resources
    cloudwatch_alarms      = "15+"
    cloudwatch_dashboards = 1
    sns_topics             = 1
    log_groups             = 2 + (var.enable_efs ? 1 : 0) + (var.enable_vpc_flow_logs ? 1 : 0)
    
    # Security Services
    guardduty_detectors    = var.enable_guardduty ? 1 : 0
    config_recorders       = var.enable_config ? 1 : 0
    cloudtrails            = var.enable_cloudtrail ? 1 : 0
  }
}

# Cost Estimation (approximate)
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD, approximate)"
  value = {
    note = "Costs are estimates and may vary based on usage and AWS pricing changes"
    
    # Compute Costs
    ec2_instances = "~$25-75 (${var.instance_type}, ${var.asg_min_size}-${var.asg_max_size} instances)"
    load_balancer = "~$20-25 (Application Load Balancer)"
    ebs_storage   = "~$3-10 (${var.root_volume_size}GB gp3 volumes)"
    
    # Storage Costs
    efs_storage   = var.enable_efs ? "~$10-50 (depending on usage)" : "$0 (disabled)"
    s3_storage    = "~$1-5 (backups and logs)"
    
    # Network Costs
    data_transfer = "~$5-20 (depending on traffic)"
    nat_gateways  = var.create_vpc ? "~$45-90 (NAT Gateway charges)" : "$0 (using existing VPC)"
    
    # Monitoring Costs
    cloudwatch    = "~$5-15 (metrics, logs, and alarms)"
    
    # Security Services Costs
    guardduty     = var.enable_guardduty ? "~$3-10 (threat detection)" : "$0"
    config        = var.enable_config ? "~$2-8 (configuration recording)" : "$0"
    cloudtrail    = var.enable_cloudtrail ? "~$2-5 (API logging)" : "$0"
    
    # Total Estimates
    total_minimum = var.enable_efs ? "~$116-283/month" : "~$106-233/month"
    total_maximum = var.enable_efs ? "~$116-283/month" : "~$106-233/month"
    
    cost_optimization_notes = [
      "Use Spot Instances for non-production environments",
      "Enable EFS Intelligent Tiering for cost savings",
      "Set up S3 lifecycle policies for log retention",
      "Monitor and right-size instances based on usage",
      "Consider Reserved Instances for production workloads"
    ]
  }
}
