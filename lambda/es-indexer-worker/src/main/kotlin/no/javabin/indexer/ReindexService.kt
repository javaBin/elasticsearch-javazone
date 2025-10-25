package no.javabin.indexer

import org.slf4j.LoggerFactory

class ReindexService(
    private val moresleepClient: MoresleepClient,
    private val esClient: ElasticsearchClient
) {
    private val logger = LoggerFactory.getLogger(ReindexService::class.java)

    fun reindexConferences(conferenceIds: List<String>) {
        logger.info("Starting reindex for conferences: $conferenceIds")

        for (confId in conferenceIds) {
            try {
                logger.info("Reindexing conference: $confId")
                val talks = moresleepClient.fetchAllTalksForConference(confId)

                logger.info("Found ${talks.size} talks for conference $confId")

                var successCount = 0
                var errorCount = 0

                for ((index, talk) in talks.withIndex()) {
                    try {
                        val talkId = talk.requiredString("id")
                        val esDocument = TalkTransformer.transform(talk)
                        esClient.indexDocument(talkId, esDocument)
                        successCount++

                        if ((index + 1) % 10 == 0) {
                            logger.info("Progress: ${index + 1}/${talks.size} talks indexed")
                        }
                    } catch (e: Exception) {
                        logger.error("Error indexing talk at position $index", e)
                        errorCount++
                    }
                }

                logger.info("Completed reindexing conference: $confId (success: $successCount, errors: $errorCount)")
            } catch (e: Exception) {
                logger.error("Error reindexing conference $confId", e)
            }
        }

        logger.info("Reindex complete for all conferences")
    }
}
