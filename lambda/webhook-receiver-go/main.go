package main

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/aws/aws-sdk-go-v2/service/sqs/types"
	"github.com/aws/aws-sdk-go-v2/aws"
)

var sqsClient *sqs.Client
var queueURL string
var webhookSecret string

func init() {
	cfg, err := config.LoadDefaultConfig(context.TODO())
	if err != nil {
		panic(fmt.Sprintf("unable to load SDK config: %v", err))
	}

	sqsClient = sqs.NewFromConfig(cfg)
	queueURL = os.Getenv("SQS_QUEUE_URL")
	webhookSecret = os.Getenv("WEBHOOK_SECRET")
}

func handler(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	// Health check
	if request.Path == "/health" {
		return events.APIGatewayProxyResponse{
			StatusCode: 200,
			Body:       "OK",
		}, nil
	}

	// Get headers (case-insensitive)
	signature := getHeader(request.Headers, "X-Webhook-Signature")
	eventType := getHeader(request.Headers, "X-Event-Type")
	eventID := getHeader(request.Headers, "X-Event-Id")

	// Verify HMAC signature
	if !verifySignature(request.Body, signature, webhookSecret) {
		return events.APIGatewayProxyResponse{
			StatusCode: 401,
			Body:       `{"error":"Invalid signature"}`,
			Headers:    map[string]string{"Content-Type": "application/json"},
		}, nil
	}

	// Send to SQS
	_, err := sqsClient.SendMessage(ctx, &sqs.SendMessageInput{
		QueueUrl:    &queueURL,
		MessageBody: &request.Body,
		MessageAttributes: map[string]types.MessageAttributeValue{
			"eventType": {
				DataType:    aws.String("String"),
				StringValue: &eventType,
			},
			"eventId": {
				DataType:    aws.String("String"),
				StringValue: &eventID,
			},
		},
	})

	if err != nil {
		return events.APIGatewayProxyResponse{
			StatusCode: 500,
			Body:       fmt.Sprintf(`{"error":"%s"}`, err.Error()),
			Headers:    map[string]string{"Content-Type": "application/json"},
		}, nil
	}

	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Body:       `{"status":"queued"}`,
		Headers:    map[string]string{"Content-Type": "application/json"},
	}, nil
}

func verifySignature(payload, signature, secret string) bool {
	if signature == "" {
		return false
	}

	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(payload))
	expected := hex.EncodeToString(mac.Sum(nil))

	return signature == expected
}

func getHeader(headers map[string]string, key string) string {
	// Try exact match
	if val, ok := headers[key]; ok {
		return val
	}
	// Try lowercase
	if val, ok := headers[key]; ok {
		return val
	}
	return ""
}

func main() {
	lambda.Start(handler)
}
