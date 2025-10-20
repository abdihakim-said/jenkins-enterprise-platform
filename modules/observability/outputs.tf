output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = "http://${aws_lb.observability.dns_name}/grafana"
}

output "prometheus_url" {
  description = "Prometheus URL (internal)"
  value       = "http://${aws_lb.observability.dns_name}/prometheus"
}

output "alertmanager_url" {
  description = "AlertManager URL (internal)"
  value       = "http://${aws_lb.observability.dns_name}/alertmanager"
}

output "observability_alb_dns" {
  description = "Observability ALB DNS name"
  value       = aws_lb.observability.dns_name
}

output "observability_alb_zone_id" {
  description = "Observability ALB hosted zone ID"
  value       = aws_lb.observability.zone_id
}

output "efs_file_system_id" {
  description = "EFS file system ID for observability data"
  value       = aws_efs_file_system.observability.id
}

output "efs_dns_name" {
  description = "EFS DNS name"
  value       = aws_efs_file_system.observability.dns_name
}

output "metrics_storage_bucket" {
  description = "S3 bucket for long-term metrics storage"
  value       = aws_s3_bucket.metrics_storage.bucket
}

output "ecs_cluster_name" {
  description = "ECS cluster name for observability stack"
  value       = aws_ecs_cluster.observability.name
}

output "prometheus_access_point_id" {
  description = "Prometheus EFS access point ID"
  value       = aws_efs_access_point.prometheus.id
}

output "grafana_access_point_id" {
  description = "Grafana EFS access point ID"
  value       = aws_efs_access_point.grafana.id
}

output "alertmanager_access_point_id" {
  description = "AlertManager EFS access point ID"
  value       = aws_efs_access_point.alertmanager.id
}
