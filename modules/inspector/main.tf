# AWS Inspector Module for Vulnerability Scanning
# Author: Abdihakim Said
# Epic 4: Story 5.4: Jenkins Master Vulnerability scanning

# Note: AWS Inspector Classic is being deprecated. Using Inspector V2 approach.
# For now, we'll create a placeholder that can be activated when needed.

# CloudWatch Event Rule for Inspector findings (when Inspector is manually enabled)
resource "aws_cloudwatch_event_rule" "inspector_findings" {
  name        = "${var.environment}-${var.project_name}-inspector-findings"
  description = "Capture Inspector findings when Inspector is enabled"

  event_pattern = jsonencode({
    source      = ["aws.inspector2"]
    detail-type = ["Inspector2 Finding"]
  })

  tags = var.tags
}

# SNS Topic for Inspector notifications
resource "aws_sns_topic" "inspector_notifications" {
  name              = "${var.environment}-${var.project_name}-inspector-notifications"
  kms_master_key_id = var.kms_key_id

  tags = merge(var.tags, {
    Name = "${var.environment}-${var.project_name}-inspector-notifications"
    Type = "Inspector Notifications"
  })
}

# CloudWatch Event Target to send findings to SNS
resource "aws_cloudwatch_event_target" "inspector_sns" {
  rule      = aws_cloudwatch_event_rule.inspector_findings.name
  target_id = "InspectorSNSTarget"
  arn       = aws_sns_topic.inspector_notifications.arn
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "inspector_notifications" {
  arn = aws_sns_topic.inspector_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.inspector_notifications.arn
      }
    ]
  })
}

# Lambda function for processing Inspector findings (optional)
resource "aws_lambda_function" "inspector_processor" {
  filename      = "${path.module}/inspector_processor.zip"
  function_name = "${var.environment}-${var.project_name}-inspector-processor"
  role          = aws_iam_role.inspector_lambda.arn
  handler       = "index.handler"
  runtime       = "python3.9"
  timeout       = 60

  # Create a simple zip file if it doesn't exist
  depends_on = [data.archive_file.inspector_processor]

  tags = var.tags
}

# Create the Lambda deployment package
data "archive_file" "inspector_processor" {
  type        = "zip"
  output_path = "${path.module}/inspector_processor.zip"

  source {
    content  = <<EOF
import json
import boto3

def handler(event, context):
    """
    Process Inspector findings and take appropriate actions
    """
    print(f"Received Inspector finding: {json.dumps(event)}")
    
    # Add your custom logic here:
    # - Parse finding severity
    # - Send notifications
    # - Create tickets
    # - Trigger remediation
    
    return {
        'statusCode': 200,
        'body': json.dumps('Inspector finding processed successfully')
    }
EOF
    filename = "index.py"
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "inspector_lambda" {
  name = "${var.environment}-${var.project_name}-inspector-lambda-role"

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

  tags = var.tags
}

# IAM Policy for Lambda
resource "aws_iam_role_policy" "inspector_lambda" {
  name = "${var.environment}-${var.project_name}-inspector-lambda-policy"
  role = aws_iam_role.inspector_lambda.id

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
          "inspector2:GetFindings",
          "inspector2:ListFindings"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda permission for SNS
resource "aws_lambda_permission" "inspector_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.inspector_processor.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.inspector_notifications.arn
}

# SNS Subscription to Lambda
resource "aws_sns_topic_subscription" "inspector_lambda" {
  topic_arn = aws_sns_topic.inspector_notifications.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.inspector_processor.arn
}

data "aws_region" "current" {}
