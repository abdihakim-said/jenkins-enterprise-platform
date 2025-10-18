output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.jenkins_alb.arn
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.jenkins_alb.dns_name
}

output "alb_zone_id" {
  description = "ALB zone ID"
  value       = aws_lb.jenkins_alb.zone_id
}

output "target_group_arn" {
  description = "Target group ARN"
  value       = aws_lb_target_group.jenkins_tg.arn
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix"
  value       = aws_lb.jenkins_alb.arn_suffix
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix"
  value       = aws_lb_target_group.jenkins_tg.arn_suffix
}
