output "webhook_url" {
  value       = "${aws_apigatewayv2_api.webhook.api_endpoint}/webhook"
  description = "⭐ Use this URL in moresleep WEBHOOK_ENDPOINT configuration"
}

output "sqs_queue_url" {
  value = aws_sqs_queue.main.url
}

output "sqs_dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "elasticsearch_endpoint" {
  value       = "http://elasticsearch.javazone.internal:9200"
  description = "Elasticsearch endpoint (via service discovery)"
}

output "webhook_receiver_lambda" {
  value = aws_lambda_function.webhook_receiver.function_name
}

output "es_indexer_lambda" {
  value = aws_lambda_function.es_indexer.function_name
}

output "elasticsearch_cluster" {
  value = aws_ecs_cluster.es_cluster.name
}
