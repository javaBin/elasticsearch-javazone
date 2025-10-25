package no.javabin.webhook

import com.amazonaws.services.lambda.runtime.Context
import com.amazonaws.services.lambda.runtime.RequestHandler
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyRequestEvent
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyResponseEvent
import software.amazon.awssdk.regions.Region
import software.amazon.awssdk.services.sqs.SqsClient
import software.amazon.awssdk.services.sqs.model.MessageAttributeValue
import software.amazon.awssdk.services.sqs.model.SendMessageRequest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

class LambdaHandler : RequestHandler<APIGatewayProxyRequestEvent, APIGatewayProxyResponseEvent> {

    private val sqsClient: SqsClient = SqsClient.builder()
        .region(Region.of(System.getenv("AWS_REGION") ?: "eu-central-1"))
        .build()

    private val queueUrl = System.getenv("SQS_QUEUE_URL")
        ?: throw IllegalStateException("SQS_QUEUE_URL not set")
    private val webhookSecret = System.getenv("WEBHOOK_SECRET")
        ?: throw IllegalStateException("WEBHOOK_SECRET not set")

    override fun handleRequest(input: APIGatewayProxyRequestEvent, context: Context): APIGatewayProxyResponseEvent {
        val logger = context.logger

        return try {
            // Handle health check
            if (input.path == "/health") {
                return APIGatewayProxyResponseEvent()
                    .withStatusCode(200)
                    .withBody("OK")
            }

            val body = input.body ?: ""
            val signature = input.headers?.get("X-Webhook-Signature")
                ?: input.headers?.get("x-webhook-signature")
            val eventType = input.headers?.get("X-Event-Type")
                ?: input.headers?.get("x-event-type")
                ?: "unknown"
            val eventId = input.headers?.get("X-Event-Id")
                ?: input.headers?.get("x-event-id")
                ?: "unknown"

            // Validate signature
            if (!verifySignature(body, signature, webhookSecret)) {
                logger.log("Invalid webhook signature for event $eventId")
                return APIGatewayProxyResponseEvent()
                    .withStatusCode(401)
                    .withBody("{\"error\":\"Invalid signature\"}")
            }

            logger.log("Received webhook event: $eventType (id: $eventId)")

            // Send to SQS
            val messageRequest = SendMessageRequest.builder()
                .queueUrl(queueUrl)
                .messageBody(body)
                .messageAttributes(mapOf(
                    "eventType" to stringAttribute(eventType),
                    "eventId" to stringAttribute(eventId)
                ))
                .build()

            sqsClient.sendMessage(messageRequest)

            logger.log("Queued webhook event: $eventType (id: $eventId)")

            APIGatewayProxyResponseEvent()
                .withStatusCode(200)
                .withBody("{\"status\":\"queued\"}")
                .withHeaders(mapOf("Content-Type" to "application/json"))

        } catch (e: Exception) {
            logger.log("Error processing webhook: ${e.message}")
            APIGatewayProxyResponseEvent()
                .withStatusCode(500)
                .withBody("{\"error\":\"${e.message}\"}")
                .withHeaders(mapOf("Content-Type" to "application/json"))
        }
    }

    private fun verifySignature(payload: String, signature: String?, secret: String): Boolean {
        if (signature == null) return false

        return try {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(secret.toByteArray(), "HmacSHA256"))
            val expected = mac.doFinal(payload.toByteArray())
                .joinToString("") { "%02x".format(it) }

            signature == expected
        } catch (e: Exception) {
            false
        }
    }

    private fun stringAttribute(value: String): MessageAttributeValue =
        MessageAttributeValue.builder()
            .dataType("String")
            .stringValue(value)
            .build()
}
