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
  handler       = "bootstrap"
  runtime       = "provided.al2"
  timeout       = 30
  memory_size   = 128

  filename         = "../lambda/webhook-receiver-go/function.zip"
  source_code_hash = filebase64sha256("../lambda/webhook-receiver-go/function.zip")

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
  handler       = "bootstrap"
  runtime       = "provided.al2"
  timeout       = 300
  memory_size   = 256

  filename         = "../lambda/es-indexer-worker-go/function.zip"
  source_code_hash = filebase64sha256("../lambda/es-indexer-worker-go/function.zip")

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
# Elasticsearch on Coolify
################################################################################
#
# Elasticsearch is deployed on Coolify (external to this Terraform)
#
# Setup in Coolify:
# 1. Deploy elasticsearch:8.11.0 container
# 2. Set environment variables:
#    - discovery.type=single-node
#    - xpack.security.enabled=true
#    - ELASTIC_PASSWORD=<use var.elasticsearch_password>
#    - ES_JAVA_OPTS=-Xms1g -Xmx1g
# 3. Expose port 9200
# 4. Add persistent volume for /usr/share/elasticsearch/data
# 5. Note the URL (e.g., http://elasticsearch.your-domain.com:9200)
# 6. Create index using config/index-mapping.json
#
# Cost: Depends on your Coolify hosting (~$0-10/month)
################################################################################

