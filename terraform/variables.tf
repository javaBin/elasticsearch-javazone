variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

# Note: VPC/subnets not needed for Lambda-only deployment
# Elasticsearch runs on Coolify (external)

variable "elasticsearch_password" {
  description = "Elasticsearch password"
  type        = string
  sensitive   = true
}

variable "elasticsearch_url" {
  description = "Elasticsearch URL"
  type        = string
  default     = "http://elasticsearch.javazone.internal:9200"
}

variable "elasticsearch_username" {
  description = "Elasticsearch username"
  type        = string
  default     = "elastic"
}

variable "elasticsearch_index" {
  description = "Elasticsearch index name"
  type        = string
  default     = "javazone_talks"
}

variable "webhook_secret" {
  description = "HMAC secret for webhook validation"
  type        = string
  sensitive   = true
}

variable "moresleep_url" {
  description = "Moresleep API URL"
  type        = string
}

variable "moresleep_username" {
  description = "Moresleep username"
  type        = string
  default     = ""
}

variable "moresleep_password" {
  description = "Moresleep password"
  type        = string
  sensitive   = true
  default     = ""
}
