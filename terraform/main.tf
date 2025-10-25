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
    key     = "elasticsearch-javazone/terraform.tfstate"
    region  = "eu-central-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
}

################################################################################
# SQS Queues
################################################################################

resource "aws_sqs_queue" "dlq" {
  name                      = "javazone-talk-events-dlq"
  message_retention_seconds = 1209600  # 14 days
}

resource "aws_sqs_queue" "main" {
  name                       = "javazone-talk-events"
  message_retention_seconds  = 345600  # 4 days
  visibility_timeout_seconds = 300     # 5 minutes (Lambda timeout)
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

################################################################################
# webhook-receiver Lambda
################################################################################

resource "aws_iam_role" "webhook_receiver_role" {
  name = "webhook-receiver-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "webhook_receiver_basic" {
  role       = aws_iam_role.webhook_receiver_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "webhook_receiver_sqs" {
  name = "sqs-send"
  role = aws_iam_role.webhook_receiver_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage", "sqs:GetQueueUrl"]
      Resource = aws_sqs_queue.main.arn
    }]
  })
}

resource "aws_lambda_function" "webhook_receiver" {
  function_name = "webhook-receiver"
  role          = aws_iam_role.webhook_receiver_role.arn
  handler       = "no.javabin.webhook.LambdaHandler::handleRequest"
  runtime       = "java11"
  timeout       = 30
  memory_size   = 512

  filename         = "../lambda/webhook-receiver/target/webhook-receiver-1.0.0-jar-with-dependencies.jar"
  source_code_hash = filebase64sha256("../lambda/webhook-receiver/target/webhook-receiver-1.0.0-jar-with-dependencies.jar")

  environment {
    variables = {
      SQS_QUEUE_URL  = aws_sqs_queue.main.url
      WEBHOOK_SECRET = var.webhook_secret
      AWS_REGION     = var.aws_region
    }
  }
}

resource "aws_apigatewayv2_api" "webhook" {
  name          = "webhook-receiver-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "webhook" {
  api_id             = aws_apigatewayv2_api.webhook.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.webhook_receiver.arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "webhook_post" {
  api_id    = aws_apigatewayv2_api.webhook.id
  route_key = "POST /webhook"
  target    = "integrations/${aws_apigatewayv2_integration.webhook.id}"
}

resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.webhook.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.webhook.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.webhook.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webhook_receiver.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.webhook.execution_arn}/*/*"
}

################################################################################
# es-indexer-worker Lambda
################################################################################

resource "aws_iam_role" "es_indexer_role" {
  name = "es-indexer-worker-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "es_indexer_basic" {
  role       = aws_iam_role.es_indexer_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "es_indexer_sqs" {
  name = "sqs-access"
  role = aws_iam_role.es_indexer_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:ChangeMessageVisibility"
      ]
      Resource = aws_sqs_queue.main.arn
    }]
  })
}

resource "aws_lambda_function" "es_indexer" {
  function_name = "es-indexer-worker"
  role          = aws_iam_role.es_indexer_role.arn
  handler       = "no.javabin.indexer.LambdaHandler::handleRequest"
  runtime       = "java11"
  timeout       = 300
  memory_size   = 1024

  filename         = "../lambda/es-indexer-worker/target/es-indexer-worker-1.0.0-jar-with-dependencies.jar"
  source_code_hash = filebase64sha256("../lambda/es-indexer-worker/target/es-indexer-worker-1.0.0-jar-with-dependencies.jar")

  environment {
    variables = {
      MORESLEEP_API_URL      = var.moresleep_url
      MORESLEEP_USERNAME     = var.moresleep_username
      MORESLEEP_PASSWORD     = var.moresleep_password
      ELASTICSEARCH_URL      = var.elasticsearch_url
      ELASTICSEARCH_USERNAME = var.elasticsearch_username
      ELASTICSEARCH_PASSWORD = var.elasticsearch_password
      ELASTICSEARCH_INDEX    = var.elasticsearch_index
      AWS_REGION             = var.aws_region
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.main.arn
  function_name    = aws_lambda_function.es_indexer.arn
  batch_size       = 10
  enabled          = true
}

################################################################################
# Elasticsearch on Fargate
################################################################################

# SSM Parameter for ES password
resource "aws_ssm_parameter" "elasticsearch_password_ssm" {
  name  = "/javazone/elasticsearch/password"
  type  = "SecureString"
  value = var.elasticsearch_password
}

# Security Group for Elasticsearch
resource "aws_security_group" "elasticsearch" {
  name        = "elasticsearch-javazone"
  description = "Elasticsearch for JavaZone"
  vpc_id      = var.vpc_id

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
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "es_execution_role" {
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

resource "aws_iam_role_policy_attachment" "es_execution_role_policy" {
  role       = aws_iam_role.es_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "es_execution_ssm_policy" {
  name = "ssm-access"
  role = aws_iam_role.es_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameters", "ssm:GetParameter"]
      Resource = aws_ssm_parameter.elasticsearch_password_ssm.arn
    }]
  })
}

# IAM Role for ECS Task
resource "aws_iam_role" "es_task_role" {
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
}

resource "aws_efs_mount_target" "elasticsearch_data" {
  for_each = toset(var.es_subnet_ids)

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
}

# ECS Cluster
resource "aws_ecs_cluster" "es_cluster" {
  name = "elasticsearch-javazone"
}

# ECS Task Definition
resource "aws_ecs_task_definition" "elasticsearch" {
  family                   = "elasticsearch-javazone"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.es_execution_role.arn
  task_role_arn            = aws_iam_role.es_task_role.arn

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
      valueFrom = aws_ssm_parameter.elasticsearch_password_ssm.arn
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
  name             = "elasticsearch-javazone"
  cluster          = aws_ecs_cluster.es_cluster.id
  task_definition  = aws_ecs_task_definition.elasticsearch.arn
  desired_count    = 1
  launch_type      = "FARGATE"
  platform_version = "1.4.0"

  network_configuration {
    subnets          = var.es_subnet_ids
    security_groups  = [aws_security_group.elasticsearch.id]
    assign_public_ip = var.assign_public_ip
  }

  service_registries {
    registry_arn = aws_service_discovery_service.elasticsearch.arn
  }
}

# Service Discovery
resource "aws_service_discovery_private_dns_namespace" "main" {
  name = "javazone.internal"
  vpc  = var.vpc_id
}

resource "aws_service_discovery_service" "elasticsearch" {
  name = "elasticsearch"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}
