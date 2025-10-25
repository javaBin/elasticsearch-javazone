package no.javabin.indexer

import org.slf4j.LoggerFactory
import software.amazon.awssdk.regions.Region
import software.amazon.awssdk.services.sqs.SqsClient
import software.amazon.awssdk.services.sqs.model.*
import org.jsonbuddy.JsonObject
import org.jsonbuddy.parse.JsonParser
import java.util.concurrent.TimeUnit

fun main() {
    val logger = LoggerFactory.getLogger("IndexerWorker")

    val awsRegion = System.getenv("AWS_REGION") ?: "eu-west-1"
    val sqsClient = SqsClient.builder()
        .region(Region.of(awsRegion))
        .build()

    val queueUrl = System.getenv("SQS_QUEUE_URL")
        ?: throw IllegalStateException("SQS_QUEUE_URL not set")
    val pollInterval = System.getenv("POLL_INTERVAL_SECONDS")?.toLong() ?: 5
    val maxMessages = System.getenv("MAX_MESSAGES_PER_POLL")?.toInt() ?: 10

    val moresleepClient = MoresleepClient()
    val elasticsearchClient = ElasticsearchClient()

    logger.info("ES Indexer Worker started")
    logger.info("Queue: $queueUrl")
    logger.info("Poll interval: ${pollInterval}s")
    logger.info("AWS Region: $awsRegion")

    // Check if reindex on start is enabled
    if (System.getenv("REINDEX_ON_START") == "true") {
        logger.info("Reindex on start enabled")
        val conferenceIds = System.getenv("REINDEX_CONFERENCE_IDS")?.split(",") ?: emptyList()
        if (conferenceIds.isNotEmpty()) {
            ReindexService(moresleepClient, elasticsearchClient).reindexConferences(conferenceIds)
        } else {
            logger.warn("REINDEX_ON_START=true but REINDEX_CONFERENCE_IDS is empty")
        }
    }

    // Main poll loop
    logger.info("Starting message polling...")
    while (true) {
        try {
            val receiveRequest = ReceiveMessageRequest.builder()
                .queueUrl(queueUrl)
                .maxNumberOfMessages(maxMessages)
                .waitTimeSeconds(20) // Long polling
                .messageAttributeNames("All")
                .build()

            val messages = sqsClient.receiveMessage(receiveRequest).messages()

            if (messages.isEmpty()) {
                logger.debug("No messages in queue")
            } else {
                logger.info("Received ${messages.size} messages")
            }

            for (message in messages) {
                try {
                    processMessage(message, moresleepClient, elasticsearchClient, logger)

                    // Delete message from queue (success)
                    sqsClient.deleteMessage(
                        DeleteMessageRequest.builder()
                            .queueUrl(queueUrl)
                            .receiptHandle(message.receiptHandle())
                            .build()
                    )

                    logger.debug("Deleted message from queue: ${message.messageId()}")

                } catch (e: Exception) {
                    logger.error("Error processing message: ${message.messageId()}", e)
                    // Don't delete - will be retried or moved to DLQ after max attempts
                }
            }

        } catch (e: Exception) {
            logger.error("Error polling queue", e)
            TimeUnit.SECONDS.sleep(pollInterval)
        }

        TimeUnit.SECONDS.sleep(pollInterval)
    }
}

fun processMessage(
    message: Message,
    moresleepClient: MoresleepClient,
    esClient: ElasticsearchClient,
    logger: org.slf4j.Logger
) {
    val body = JsonParser.parseToObject(message.body())
    val eventType = body.requiredString("eventType")
    val entityId = body.requiredString("entityId")

    logger.info("Processing event: $eventType for entity: $entityId")

    when (eventType) {
        "talk.created", "talk.updated", "talk.published" -> {
            // Fetch fresh data from moresleep API
            val talkData = moresleepClient.fetchTalk(entityId)

            // Transform to ES document
            val esDocument = TalkTransformer.transform(talkData)

            // Index to Elasticsearch
            esClient.indexDocument(entityId, esDocument)

            logger.info("Successfully indexed talk: $entityId")
        }
        "talk.unpublished" -> {
            // Update status field to DRAFT (or could delete)
            esClient.updateDocument(entityId, mapOf("status" to "DRAFT"))

            logger.info("Updated unpublished talk: $entityId")
        }
        else -> {
            logger.warn("Unknown event type: $eventType")
        }
    }
}
