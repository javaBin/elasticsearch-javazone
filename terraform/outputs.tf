output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  value = aws_ecs_service.elasticsearch.name
}

output "efs_file_system_id" {
  value       = aws_efs_file_system.elasticsearch_data.id
  description = "EFS file system ID for Elasticsearch data"
}

output "service_discovery_endpoint" {
  value       = var.enable_service_discovery ? "elasticsearch.javazone.internal:9200" : "Use task IP"
  description = "Elasticsearch endpoint (DNS name if service discovery enabled)"
}

output "elasticsearch_url_template" {
  value       = var.enable_service_discovery ? "http://elasticsearch.javazone.internal:9200" : "http://<task-ip>:9200"
  description = "Template URL for Elasticsearch"
}
