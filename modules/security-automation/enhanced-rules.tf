# Enhanced Security Rules for Jenkins Enterprise Platform
# Additional Config rules and security monitoring

# MFA for root account
resource "aws_config_config_rule" "mfa_enabled_for_root" {
  name = "${var.environment}-mfa-enabled-for-root"

  source {
    owner             = "AWS"
    source_identifier = "MFA_ENABLED_FOR_IAM_CONSOLE_ACCESS"
  }
}

# Security group rules
resource "aws_config_config_rule" "security_group_ssh_check" {
  name = "${var.environment}-security-group-ssh-check"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }
}

# CloudTrail encryption
resource "aws_config_config_rule" "cloudtrail_encryption" {
  name = "${var.environment}-cloudtrail-encryption-enabled"

  source {
    owner             = "AWS"
    source_identifier = "CLOUD_TRAIL_ENCRYPTION_ENABLED"
  }
}

# IAM password policy
resource "aws_config_config_rule" "iam_password_policy" {
  name = "${var.environment}-iam-password-policy"

  source {
    owner             = "AWS"
    source_identifier = "IAM_PASSWORD_POLICY"
  }

  input_parameters = jsonencode({
    RequireUppercaseCharacters = "true"
    RequireLowercaseCharacters = "true"
    RequireSymbols            = "true"
    RequireNumbers            = "true"
    MinimumPasswordLength     = "14"
    PasswordReusePrevention   = "24"
    MaxPasswordAge            = "90"
  })
}

# Enhanced EventBridge rule for Config compliance
resource "aws_cloudwatch_event_rule" "config_compliance" {
  name        = "${var.environment}-jenkins-config-compliance"
  description = "Capture Config compliance changes"

  event_pattern = jsonencode({
    source      = ["aws.config"]
    detail-type = ["Config Rules Compliance Change"]
    detail = {
      newEvaluationResult = {
        complianceType = ["NON_COMPLIANT"]
      }
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "config_compliance_lambda" {
  rule      = aws_cloudwatch_event_rule.config_compliance.name
  target_id = "ConfigComplianceTarget"
  arn       = aws_lambda_function.security_responder.arn
}

# Lambda permission for Config events
resource "aws_lambda_permission" "allow_config_eventbridge" {
  statement_id  = "AllowExecutionFromConfigEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_responder.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.config_compliance.arn
}
