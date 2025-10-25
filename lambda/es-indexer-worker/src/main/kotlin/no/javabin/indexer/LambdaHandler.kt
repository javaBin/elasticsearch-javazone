package no.javabin.indexer

import com.amazonaws.services.lambda.runtime.Context
import com.amazonaws.services.lambda.runtime.RequestHandler
import com.amazonaws.services.lambda.runtime.events.SQSEvent
import org.jsonbuddy.parse.JsonParser

class LambdaHandler : RequestHandler<SQSEvent, String> {

    private val moresleepClient = MoresleepClient()
    private val elasticsearchClient = ElasticsearchClient()

    override fun handleRequest(event: SQSEvent, context: Context): String {
        val logger = context.logger
        var successCount = 0
        var errorCount = 0

        for (record in event.records) {
            try {
                val body = JsonParser.parseToObject(record.body)
                val eventType = body.requiredString("eventType")
                val entityId = body.requiredString("entityId")

                logger.log("Processing event: $eventType for entity: $entityId")

                when (eventType) {
                    "talk.created", "talk.updated", "talk.published" -> {
                        // Fetch fresh data from moresleep
                        val talkData = moresleepClient.fetchTalk(entityId)

                        // Transform to ES document
                        val esDocument = TalkTransformer.transform(talkData)

                        // Index to Elasticsearch
                        elasticsearchClient.indexDocument(entityId, esDocument)

                        logger.log("Successfully indexed talk: $entityId")
                        successCount++
                    }
                    "talk.unpublished" -> {
                        // Update status to DRAFT
                        elasticsearchClient.updateDocument(entityId, mapOf("status" to "DRAFT"))
                        logger.log("Updated unpublished talk: $entityId")
                        successCount++
                    }
                    else -> {
                        logger.log("Unknown event type: $eventType")
                    }
                }
            } catch (e: Exception) {
                logger.log("Error processing message: ${e.message}")
                errorCount++
                // Lambda will automatically retry on exception
                throw e
            }
        }

        return "Processed ${successCount} messages successfully, ${errorCount} errors"
    }
}
