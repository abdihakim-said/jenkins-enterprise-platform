# IAM Module - Main Configuration
# Author: Abdihakim Said

# Jenkins IAM Role
resource "aws_iam_role" "jenkins" {
  name = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-jenkins-role"

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

  tags = merge(var.tags, {
    Name = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-jenkins-role"
    Type = "Jenkins IAM Role"
  })
}

# Jenkins IAM Policy
resource "aws_iam_policy" "jenkins" {
  name        = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-jenkins-policy"
  description = "IAM policy for Jenkins instances"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          # SSM permissions for Session Manager and parameter store
          "ssm:UpdateInstanceInformation",
          "ssm:SendCommand",
          "ssm:ListCommands",
          "ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation",
          "ssm:GetCommandInvocation",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ssm:PutParameter",
          "ssm:DeleteParameter",
          "ssm:DescribeParameters"
        ]
        Resource = [
          "arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/jenkins/*",
          "arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:document/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:instance/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          # CloudWatch permissions for logging and metrics
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = [
          "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/jenkins/*",
          "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/jenkins/*",
          "arn:aws:cloudwatch:*:${data.aws_caller_identity.current.account_id}:metric/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          # EC2 permissions for Jenkins agents
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:DescribeKeyPairs",
          "ec2:DescribeRegions",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:StopInstances",
          "ec2:CreateTags",
          "ec2:DescribeTags",
          # Packer permissions for AMI building
          "ec2:CreateKeyPair",
          "ec2:DeleteKeyPair",
          "ec2:CreateImage",
          "ec2:RegisterImage",
          "ec2:DeregisterImage",
          "ec2:CopyImage",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot",
          "ec2:DescribeSnapshots",
          "ec2:ModifyImageAttribute",
          "ec2:ModifyInstanceAttribute",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress"
        ]
        Resource = [
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:instance/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:image/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:snapshot/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:security-group/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:key-pair/*",
          "arn:aws:ec2:*::image/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          # S3 permissions for artifacts and backups
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::jenkins-*",
          "arn:aws:s3:::jenkins-*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          # EFS permissions
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets"
        ]
        Resource = [
          "arn:aws:elasticfilesystem:*:${data.aws_caller_identity.current.account_id}:file-system/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          # Auto Scaling permissions for self-healing
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:SetInstanceHealth"
        ]
        Resource = [
          "arn:aws:autoscaling:*:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/jenkins-*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          # ELB permissions for health checks
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTargetGroups"
        ]
        Resource = [
          "arn:aws:elasticloadbalancing:*:${data.aws_caller_identity.current.account_id}:targetgroup/jenkins-*/*",
          "arn:aws:elasticloadbalancing:*:${data.aws_caller_identity.current.account_id}:loadbalancer/app/jenkins-*/*"
        ]
      }
    ]
  })

  tags = var.tags
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "jenkins" {
  role       = aws_iam_role.jenkins.name
  policy_arn = aws_iam_policy.jenkins.arn
}

# Attach AWS managed policies
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_server_policy" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Instance Profile
resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-jenkins-profile"
  role = aws_iam_role.jenkins.name

  tags = merge(var.tags, {
    Name = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-jenkins-profile"
    Type = "Jenkins Instance Profile"
  })
}

# KMS Key for encryption
resource "aws_kms_key" "jenkins" {
  description             = "KMS key for Jenkins encryption"
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Jenkins Role"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.jenkins.arn
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-kms-key"
    Type = "Jenkins KMS Key"
  })
}

# KMS Key Alias
resource "aws_kms_alias" "jenkins" {
  name          = "alias/${var.environment}-${replace(lower(var.project_name), " ", "-")}-jenkins"
  target_key_id = aws_kms_key.jenkins.key_id
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}
