# SSM Parameters for Jenkins Enterprise Platform
# Manages credentials and configuration parameters

# Generate random password for Jenkins admin
resource "random_password" "jenkins_admin" {
  length  = 32
  special = true
}

# Store Jenkins admin password in SSM Parameter Store
resource "aws_ssm_parameter" "jenkins_admin_password" {
  name        = "/jenkins/${var.environment}/admin-password"
  description = "Jenkins admin user password for ${var.environment} environment"
  type        = "SecureString"
  value       = random_password.jenkins_admin.result

  tags = merge(var.common_tags, {
    Name        = "jenkins-admin-password-${var.environment}"
    Type        = "Jenkins Credential"
    Environment = var.environment
    Sensitive   = "true"
  })

  lifecycle {
    ignore_changes = [value]
  }
}

# Store Jenkins admin username in SSM Parameter Store
resource "aws_ssm_parameter" "jenkins_admin_username" {
  name        = "/jenkins/${var.environment}/admin-username"
  description = "Jenkins admin username for ${var.environment} environment"
  type        = "String"
  value       = var.jenkins_admin_username

  tags = merge(var.common_tags, {
    Name        = "jenkins-admin-username-${var.environment}"
    Type        = "Jenkins Configuration"
    Environment = var.environment
  })
}

# Store Jenkins URL in SSM Parameter Store
resource "aws_ssm_parameter" "jenkins_url" {
  name        = "/jenkins/${var.environment}/url"
  description = "Jenkins URL for ${var.environment} environment"
  type        = "String"
  value       = "http://${module.alb.dns_name}:8080"

  tags = merge(var.common_tags, {
    Name        = "jenkins-url-${var.environment}"
    Type        = "Jenkins Configuration"
    Environment = var.environment
  })

  depends_on = [module.alb]
}
