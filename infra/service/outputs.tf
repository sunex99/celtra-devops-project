output "service_url" {
  description = "Public URL of the service. The smoke test after a deploy calls this."
  value       = "http://${aws_lb.main.dns_name}"
}

output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.main.name
}

output "service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.app.name
}
