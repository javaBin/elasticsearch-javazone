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

variable "task_cpu" {
  description = "CPU units for Elasticsearch"
  type        = number
  default     = 1024
}

variable "task_memory" {
  description = "Memory for Elasticsearch"
  type        = number
  default     = 2048
}

variable "heap_size" {
  description = "Java heap size in MB"
  type        = number
  default     = 1024
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
