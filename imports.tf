# Import blocks for existing S3 buckets
# These were manually imported earlier but need to be declared in code

import {
  to = module.alb.aws_s3_bucket.alb_logs
  id = "dev-jenkins-alb-logs-9txu0xkg"
}

import {
  to = module.cost_optimization.aws_s3_bucket.cost_reports
  id = "dev-jenkins-cost-optimization-871xfbxm"
}

import {
  to = module.security_automation.aws_s3_bucket.cloudtrail
  id = "dev-jenkins-cloudtrail-zm5pw1bf"
}

# Import random strings that generate bucket suffixes
import {
  to = module.alb.random_string.bucket_suffix
  id = "9txu0xkg"
}

import {
  to = module.cost_optimization.random_string.bucket_suffix
  id = "871xfbxm"
}

import {
  to = module.security_automation.random_string.bucket_suffix
  id = "zm5pw1bf"
}
