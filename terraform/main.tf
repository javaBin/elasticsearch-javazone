terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket  = "javazone-terraform-state"
    key     = "elasticsearch/terraform.tfstate"
    region  = "eu-central-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Service     = "elasticsearch"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# SSM Parameter for ES password
resource "aws_ssm_parameter" "elasticsearch_password" {
  name  = "/javazone/elasticsearch/password"
  type  = "SecureString"
  value = var.elasticsearch_password
}

# Security Group for Elasticsearch
resource "aws_security_group" "elasticsearch" {
  name        = "elasticsearch-javazone"
  description = "Elasticsearch for JavaZone"
  vpc_id      = var.vpc_id

  # Allow from es-indexer-worker and libum
  ingress {
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Elasticsearch HTTP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "elasticsearch-javazone"
  }
}

# ECS Cluster for Elasticsearch
resource "aws_ecs_cluster" "main" {
  name = "elasticsearch-javazone"
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "execution_role" {
  name = "elasticsearch-javazone-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution_role_policy" {
  role       = aws_iam_role.execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_ssm_policy" {
  name = "ssm-access"
  role = aws_iam_role.execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:GetParameters",
        "ssm:GetParameter"
      ]
      Resource = aws_ssm_parameter.elasticsearch_password.arn
    }]
  })
}

# IAM Role for ECS Task
resource "aws_iam_role" "task_role" {
  name = "elasticsearch-javazone-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

# EFS for persistent storage
resource "aws_efs_file_system" "elasticsearch_data" {
  creation_token = "elasticsearch-javazone-data"
  encrypted      = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name = "elasticsearch-javazone-data"
  }
}

resource "aws_efs_mount_target" "elasticsearch_data" {
  for_each = toset(var.subnet_ids)

  file_system_id  = aws_efs_file_system.elasticsearch_data.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

resource "aws_security_group" "efs" {
  name        = "elasticsearch-efs"
  description = "EFS for Elasticsearch data"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.elasticsearch.id]
    description     = "NFS from ES tasks"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "elasticsearch-efs"
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "elasticsearch" {
  family                   = "elasticsearch-javazone"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  volume {
    name = "elasticsearch-data"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.elasticsearch_data.id
      transit_encryption = "ENABLED"
    }
  }

  container_definitions = jsonencode([{
    name  = "elasticsearch"
    image = "docker.elastic.co/elasticsearch/elasticsearch:8.11.0"

    portMappings = [{
      containerPort = 9200
      protocol      = "tcp"
    }]

    mountPoints = [{
      sourceVolume  = "elasticsearch-data"
      containerPath = "/usr/share/elasticsearch/data"
    }]

    environment = [
      { name = "discovery.type", value = "single-node" },
      { name = "xpack.security.enabled", value = "true" },
      { name = "ES_JAVA_OPTS", value = "-Xms${var.heap_size}m -Xmx${var.heap_size}m" },
      { name = "cluster.name", value = "javazone-cluster" }
    ]

    secrets = [{
      name      = "ELASTIC_PASSWORD"
      valueFrom = aws_ssm_parameter.elasticsearch_password.arn
    }]

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:9200/_cluster/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 120
    }
  }])
}

# ECS Service
resource "aws_ecs_service" "elasticsearch" {
  name            = "elasticsearch-javazone"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.elasticsearch.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  platform_version = "1.4.0"  # Required for EFS

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.elasticsearch.id]
    assign_public_ip = var.assign_public_ip
  }

  # Use service discovery for stable DNS name
  dynamic "service_registries" {
    for_each = var.enable_service_discovery ? [1] : []
    content {
      registry_arn = aws_service_discovery_service.elasticsearch[0].arn
    }
  }
}

# Service Discovery (optional, for stable DNS name)
resource "aws_service_discovery_private_dns_namespace" "main" {
  count = var.enable_service_discovery ? 1 : 0

  name = "javazone.internal"
  vpc  = var.vpc_id
}

resource "aws_service_discovery_service" "elasticsearch" {
  count = var.enable_service_discovery ? 1 : 0

  name = "elasticsearch"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main[0].id

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}
