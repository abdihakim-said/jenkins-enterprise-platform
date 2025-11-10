# Development Environment Configuration
environment  = "dev"
project_name = "jenkins-enterprise-platform"

# Network Configuration
vpc_cidr             = "10.1.0.0/16"
public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
private_subnet_cidrs = ["10.1.10.0/24", "10.1.20.0/24", "10.1.30.0/24"]

# Jenkins Configuration - Development (smaller instances)
jenkins_instance_type     = "t3.small"
jenkins_min_size          = 1
jenkins_max_size          = 2
jenkins_desired_capacity  = 1
health_check_grace_period = 600 # 10 minutes

# Cost Optimization for Dev
single_nat_gateway         = true
enable_detailed_monitoring = false
log_retention_days         = 7
backup_retention_days      = 7

# Tags
common_tags = {
  Environment = "dev"
  Project     = "jenkins-enterprise-platform"
  ManagedBy   = "terraform"
  CostCenter  = "development"
}
