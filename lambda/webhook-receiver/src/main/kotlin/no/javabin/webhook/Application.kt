package no.javabin.webhook

import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.ktor.http.*
import org.slf4j.LoggerFactory
import software.amazon.awssdk.regions.Region
import software.amazon.awssdk.services.sqs.SqsClient
import software.amazon.awssdk.services.sqs.model.MessageAttributeValue
import software.amazon.awssdk.services.sqs.model.SendMessageRequest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

fun main() {
    embeddedServer(Netty, port = System.getenv("PORT")?.toInt() ?: 8083) {
        module()
    }.start(wait = true)
}

fun Application.module() {
    val logger = LoggerFactory.getLogger("WebhookReceiver")

    val awsRegion = System.getenv("AWS_REGION") ?: "eu-west-1"
    val sqsClient = SqsClient.builder()
        .region(Region.of(awsRegion))
        .build()

    val queueUrl = System.getenv("SQS_QUEUE_URL")
        ?: throw IllegalStateException("SQS_QUEUE_URL environment variable not set")
    val webhookSecret = System.getenv("WEBHOOK_SECRET")
        ?: throw IllegalStateException("WEBHOOK_SECRET environment variable not set")

    logger.info("Webhook Receiver started")
    logger.info("Queue URL: $queueUrl")
    logger.info("AWS Region: $awsRegion")

    routing {
        post("/webhook") {
            try {
                val body = call.receiveText()
                val signature = call.request.header("X-Webhook-Signature")
                val eventType = call.request.header("X-Event-Type")
                val eventId = call.request.header("X-Event-Id")

                // Validate signature
                if (!verifySignature(body, signature, webhookSecret)) {
                    logger.warn("Invalid webhook signature for event $eventId")
                    call.respond(HttpStatusCode.Unauthorized, "Invalid signature")
                    return@post
                }

                logger.debug("Received webhook event: $eventType (id: $eventId)")

                // Put message on SQS queue
                val messageRequest = SendMessageRequest.builder()
                    .queueUrl(queueUrl)
                    .messageBody(body)
                    .messageAttributes(mapOf(
                        "eventType" to stringAttribute(eventType ?: "unknown"),
                        "eventId" to stringAttribute(eventId ?: "unknown")
                    ))
                    .build()

                sqsClient.sendMessage(messageRequest)

                logger.info("Queued webhook event: $eventType (id: $eventId)")
                call.respond(HttpStatusCode.OK, mapOf("status" to "queued"))

            } catch (e: Exception) {
                logger.error("Error processing webhook", e)
                call.respond(HttpStatusCode.InternalServerError, mapOf("error" to (e.message ?: "Unknown error")))
            }
        }

        get("/health") {
            call.respondText("OK", status = HttpStatusCode.OK)
        }

        get("/") {
            call.respondText("JavaZone Webhook Receiver v1.0", status = HttpStatusCode.OK)
        }
    }
}

fun verifySignature(payload: String, signature: String?, secret: String): Boolean {
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

fun stringAttribute(value: String): MessageAttributeValue =
    MessageAttributeValue.builder()
        .dataType("String")
        .stringValue(value)
        .build()
