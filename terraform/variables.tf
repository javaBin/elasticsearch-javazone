variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for Elasticsearch"
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Assign public IP (true if using public subnets)"
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access Elasticsearch"
  type        = list(string)
  default     = ["10.0.0.0/8"]  # Adjust to your VPC CIDR
}

variable "elasticsearch_password" {
  description = "Elasticsearch password for elastic user"
  type        = string
  sensitive   = true
}

variable "task_cpu" {
  description = "CPU units (1024 = 1 vCPU)"
  type        = number
  default     = 1024
}

variable "task_memory" {
  description = "Memory in MB (at least 2x heap_size)"
  type        = number
  default     = 2048
}

variable "heap_size" {
  description = "Java heap size in MB (should be ~50% of task_memory)"
  type        = number
  default     = 1024
}

variable "enable_service_discovery" {
  description = "Enable service discovery for stable DNS (elasticsearch.javazone.internal)"
  type        = bool
  default     = true
}
