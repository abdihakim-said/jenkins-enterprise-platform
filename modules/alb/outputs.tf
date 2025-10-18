# ALB Module - Outputs
# Author: Abdihakim Said

output "load_balancer_id" {
  description = "ID of the load balancer"
  value       = aws_lb.jenkins.id
}

output "load_balancer_arn" {
  description = "ARN of the load balancer"
  value       = aws_lb.jenkins.arn
}

output "dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.jenkins.dns_name
}

output "zone_id" {
  description = "Zone ID of the load balancer"
  value       = aws_lb.jenkins.zone_id
}

output "target_group_id" {
  description = "ID of the target group"
  value       = aws_lb_target_group.jenkins.id
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.jenkins.arn
}

output "target_group_name" {
  description = "Name of the target group"
  value       = aws_lb_target_group.jenkins.name
}

output "listener_http_arn" {
  description = "ARN of the HTTP listener"
  value       = aws_lb_listener.jenkins_http.arn
}

output "listener_jenkins_arn" {
  description = "ARN of the Jenkins listener"
  value       = aws_lb_listener.jenkins.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for ALB logs"
  value       = aws_s3_bucket.alb_logs.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for ALB logs"
  value       = aws_s3_bucket.alb_logs.arn
}
