# Deployment Role for Infrastructure Operations
# Separate from Jenkins instance role for security isolation

resource "aws_iam_role" "deployment" {
  name = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-deployment-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.jenkins.arn
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-deployment-role"
    Type = "Infrastructure Deployment Role"
  })
}

# Deployment Role Policy - Infrastructure Creation Permissions
resource "aws_iam_role_policy" "deployment" {
  name = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-deployment-policy"
  role = aws_iam_role.deployment.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          # EC2 Read Permissions (required for Terraform data sources)
          "ec2:DescribeImages",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeKeyPairs",
          "ec2:DescribeRouteTables",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeNatGateways",
          "ec2:DescribeVpcEndpoints",
          "ec2:DescribeFlowLogs",
          "ec2:DescribeAddresses",
          "ec2:DescribeVpcAttribute",
          
          # VPC and Networking
          "ec2:CreateVpc",
          "ec2:DeleteVpc",
          "ec2:CreateSubnet",
          "ec2:DeleteSubnet",
          "ec2:CreateInternetGateway",
          "ec2:DeleteInternetGateway",
          "ec2:AttachInternetGateway",
          "ec2:DetachInternetGateway",
          "ec2:CreateNatGateway",
          "ec2:DeleteNatGateway",
          "ec2:CreateRouteTable",
          "ec2:DeleteRouteTable",
          "ec2:CreateRoute",
          "ec2:DeleteRoute",
          "ec2:AssociateRouteTable",
          "ec2:DisassociateRouteTable",
          "ec2:AllocateAddress",
          "ec2:ReleaseAddress",
          "ec2:CreateVpcEndpoint",
          "ec2:DeleteVpcEndpoint",
          "ec2:CreateFlowLogs",
          "ec2:DeleteFlowLogs",
          
          # Security Groups
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupEgress",
          
          # IAM for service roles
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:PassRole",
          
          # S3 Buckets
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:PutBucketVersioning",
          "s3:PutBucketEncryption",
          "s3:PutBucketLifecycleConfiguration",
          "s3:PutBucketPublicAccessBlock",
          
          # Lambda Functions
          "lambda:CreateFunction",
          "lambda:DeleteFunction",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:AddPermission",
          "lambda:RemovePermission",
          
          # CloudWatch and Logging
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "cloudwatch:PutDashboard",
          "cloudwatch:DeleteDashboards",
          "cloudwatch:GetDashboard",
          "cloudwatch:ListDashboards",
          "cloudwatch:PutMetricAlarm",
          "cloudwatch:DeleteAlarms",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListMetrics",
          "cloudwatch:ListTagsForResource",
          
          # EventBridge
          "events:PutRule",
          "events:DeleteRule",
          "events:PutTargets",
          "events:RemoveTargets",
          "events:DescribeRule",
          "events:ListTargetsByRule",
          "events:TagResource",
          "events:UntagResource",
          
          # SNS
          "sns:CreateTopic",
          "sns:DeleteTopic",
          "sns:Subscribe",
          "sns:Unsubscribe",
          "sns:SetTopicAttributes",
          
          # Security Services
          "guardduty:CreateDetector",
          "guardduty:DeleteDetector",
          "guardduty:TagResource",
          "guardduty:UntagResource",
          "securityhub:EnableSecurityHub",
          "securityhub:DisableSecurityHub",
          "config:PutConfigRule",
          "config:DeleteConfigRule",
          
          # EFS
          "elasticfilesystem:CreateFileSystem",
          "elasticfilesystem:DeleteFileSystem",
          "elasticfilesystem:CreateMountTarget",
          "elasticfilesystem:DeleteMountTarget",
          "elasticfilesystem:CreateAccessPoint",
          "elasticfilesystem:DeleteAccessPoint",
          "elasticfilesystem:TagResource",
          "elasticfilesystem:UntagResource",
          
          # Auto Scaling
          "autoscaling:CreateAutoScalingGroup",
          "autoscaling:DeleteAutoScalingGroup",
          "autoscaling:CreateLaunchTemplate",
          "autoscaling:DeleteLaunchTemplate",
          "autoscaling:PutScheduledUpdateGroupAction",
          "autoscaling:DeleteScheduledAction",
          
          # Load Balancer
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          
          # SSM Parameters
          "ssm:PutParameter",
          "ssm:DeleteParameter",
          "ssm:AddTagsToResource",
          "ssm:RemoveTagsFromResource",
          
          # Tagging
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          # S3 Backend for Terraform State
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketVersioning",
          "s3:GetBucketLocation",
          "s3:HeadObject",
          "s3:GetObjectVersion"
        ]
        Resource = [
          "arn:aws:s3:::jenkins-tf-state-*",
          "arn:aws:s3:::jenkins-tf-state-*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          # DynamoDB for Terraform State Locking
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = [
          "arn:aws:dynamodb:*:*:table/jenkins-terraform-locks"
        ]
      }
    ]
  })
}
