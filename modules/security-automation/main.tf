# Infrastructure Security Automation Module
# Automated threat detection, compliance monitoring, and incident response

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
    Module = "security-automation"
  })
}

# GuardDuty for threat detection
resource "aws_guardduty_detector" "main" {
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
  
  datasources {
    s3_logs {
      enable = true
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = local.common_tags
}

# Security Hub for centralized findings
resource "aws_securityhub_account" "main" {
  enable_default_standards = true
}

# Config rules for compliance (using existing Config service)


# CloudTrail for API logging
resource "aws_cloudtrail" "main" {
  name           = "${var.environment}-jenkins-cloudtrail"
  s3_bucket_name = aws_s3_bucket.cloudtrail.bucket

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = local.common_tags

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

# S3 bucket for CloudTrail
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${var.environment}-jenkins-cloudtrail-${random_string.bucket_suffix.result}"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/dev-jenkins-cloudtrail"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/dev-jenkins-cloudtrail"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lambda for automated security response
resource "aws_lambda_function" "security_responder" {
  filename      = data.archive_file.security_responder.output_path
  function_name = "${var.environment}-jenkins-security-responder"
  role          = aws_iam_role.security_responder.arn
  handler       = "security_responder.lambda_handler"
  runtime       = "python3.9"
  timeout       = 300

  environment {
    variables = {
      ENVIRONMENT   = var.environment
      SNS_TOPIC_ARN = aws_sns_topic.security_alerts.arn
    }
  }

  tags = local.common_tags
}

# EventBridge rule for GuardDuty findings
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "${var.environment}-jenkins-guardduty-findings"
  description = "Capture high severity GuardDuty findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [7.0, 8.0, 8.5, 9.0]
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "guardduty_lambda" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "SecurityResponderTarget"
  arn       = aws_lambda_function.security_responder.arn
}

# SNS topic for security alerts
resource "aws_sns_topic" "security_alerts" {
  name = "${var.environment}-jenkins-security-alerts"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Config rules for compliance
resource "aws_config_config_rule" "encrypted_volumes" {
  name = "${var.environment}-encrypted-volumes"

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }
}

resource "aws_config_config_rule" "s3_bucket_public_read_prohibited" {
  name = "${var.environment}-s3-bucket-public-read-prohibited"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random string for unique bucket names
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Archive file for Lambda function
data "archive_file" "security_responder" {
  type        = "zip"
  output_path = "${path.module}/security_responder.zip"
  
  source {
    content  = file("${path.module}/security_responder.py")
    filename = "security_responder.py"
  }
}



resource "aws_iam_role" "security_responder" {
  name = "${var.environment}-jenkins-security-responder-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "security_responder" {
  name = "${var.environment}-jenkins-security-responder-policy"
  role = aws_iam_role.security_responder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.security_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "autoscaling:UpdateAutoScalingGroup"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_responder.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_findings.arn
}
