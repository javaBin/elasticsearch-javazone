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
      ELASTICSEARCH_URL      = "https://${aws_opensearch_domain.javazone.endpoint}"
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
# OpenSearch Domain
################################################################################

# Security Group for OpenSearch
resource "aws_security_group" "opensearch" {
  name        = "opensearch-javazone"
  description = "OpenSearch for JavaZone"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "HTTPS for OpenSearch"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# OpenSearch Domain
resource "aws_opensearch_domain" "javazone" {
  domain_name    = "javazone-talks"
  engine_version = "OpenSearch_2.11"

  cluster_config {
    instance_type  = "t3.small.search"  # ~$0.036/hour = ~$26/month
    instance_count = 1
    zone_awareness_enabled = false
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10  # GB - plenty for 10K talks
    volume_type = "gp3"
  }

  vpc_options {
    subnet_ids         = [var.es_subnet_ids[0]]  # Single AZ for cost savings
    security_group_ids = [aws_security_group.opensearch.id]
  }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true
    master_user_options {
      master_user_name     = var.elasticsearch_username
      master_user_password = var.elasticsearch_password
    }
  }

  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "*"
      }
      Action   = "es:*"
      Resource = "arn:aws:es:${var.aws_region}:*:domain/javazone-talks/*"
    }]
  })

  tags = {
    Name = "javazone-talks"
  }
}

