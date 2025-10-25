variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "es_subnet_ids" {
  description = "Subnet IDs for Elasticsearch (need 2+ for EFS)"
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Assign public IP to Elasticsearch task"
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access Elasticsearch"
  type        = list(string)
}

variable "opensearch_instance_type" {
  description = "OpenSearch instance type"
  type        = string
  default     = "t3.small.search"  # ~$26/month
}

variable "opensearch_volume_size" {
  description = "EBS volume size in GB"
  type        = number
  default     = 10
}

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
