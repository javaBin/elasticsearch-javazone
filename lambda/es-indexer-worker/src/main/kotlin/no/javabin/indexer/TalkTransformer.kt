package no.javabin.indexer

import org.jsonbuddy.JsonArray
import org.jsonbuddy.JsonObject
import java.time.LocalDateTime

object TalkTransformer {
    fun transform(talkData: JsonObject): String {
        val data = talkData.requiredObject("data")

        // Extract pkomfeedbacks (comments & ratings already stored in moresleep DB!)
        val pkomfeedbacks = data.objectValue("pkomfeedbacks")
            .flatMap { it.arrayValue("value") }
            .orElse(JsonArray())

        val comments = JsonArray.fromNodeStream(
            pkomfeedbacks.objectStream()
                .filter { it.stringValue("type").orElse("") == "comment" }
                .map { comment ->
                    JsonObject()
                        .put("id", comment.stringValue("id").orElse(""))
                        .put("author", comment.stringValue("author").orElse(""))
                        .put("comment", comment.stringValue("comment").orElse(""))
                        .put("created", comment.stringValue("created").orElse(""))
                }
        )

        val ratings = JsonArray.fromNodeStream(
            pkomfeedbacks.objectStream()
                .filter { it.stringValue("type").orElse("") == "rating" }
                .map { rating ->
                    JsonObject()
                        .put("id", rating.stringValue("id").orElse(""))
                        .put("author", rating.stringValue("author").orElse(""))
                        .put("rating", rating.stringValue("rating").orElse(""))
                        .put("created", rating.stringValue("created").orElse(""))
                }
        )

        val avgRating = calculateAvgRating(ratings)

        // Build speakers array
        val speakersArray = talkData.arrayValue("speakers")
            .map { speakers ->
                JsonArray.fromNodeStream(
                    speakers.objectStream().map { speaker ->
                        JsonObject()
                            .put("speakerId", speaker.stringValue("id").orElse(""))
                            .put("name", speaker.stringValue("name").orElse(""))
                            .put("email", speaker.stringValue("email").orElse(""))
                            .put("bio", extractDataValue(speaker.requiredObject("data"), "bio"))
                    }
                )
            }
            .orElse(JsonArray())

        // Extract tags (program committee tags with authors)
        val tags = extractDataArray(data, "tags")

        // Build final ES document
        val esDocument = JsonObject()
            .put("talkId", talkData.requiredString("id"))
            .put("conferenceId", talkData.stringValue("conferenceid").orElse(""))
            .put("title", extractDataValue(data, "title"))
            .put("abstract", extractDataValue(data, "abstract"))
            .put("status", talkData.stringValue("status").orElse("DRAFT"))
            .put("format", extractDataValue(data, "format"))
            .put("language", extractDataValue(data, "language"))
            .put("length", extractDataValue(data, "length"))
            .put("tags", tags)
            .put("keywords", extractDataArray(data, "keywords"))
            .put("speakers", speakersArray)
            .put("comments", comments)
            .put("ratings", ratings)
            .put("avgRating", avgRating)
            .put("room", extractDataValue(data, "room"))
            .put("slot", extractDataValue(data, "starttime"))
            .put("lastUpdated", talkData.stringValue("lastUpdated").orElse(""))
            .put("publishedAt", talkData.stringValue("publishedAt").orElse(null))
            .put("indexed_at", LocalDateTime.now().toString())

        return esDocument.toJson()
    }

    private fun extractDataValue(data: JsonObject, key: String): String? {
        return data.objectValue(key)
            .flatMap { it.value("value") }
            .map { it.toString().trim('"') }
            .orElse(null)
    }

    private fun extractDataArray(data: JsonObject, key: String): JsonArray? {
        return data.objectValue(key)
            .flatMap { it.arrayValue("value") }
            .orElse(null)
    }

    private fun calculateAvgRating(ratings: JsonArray): Double {
        if (ratings.isEmpty) return 0.0

        val sum = ratings.objectStream()
            .mapToInt { ratingStringToInt(it.stringValue("rating").orElse("THREE")) }
            .sum()

        return sum.toDouble() / ratings.size()
    }

    private fun ratingStringToInt(rating: String): Int {
        return when (rating.uppercase()) {
            "ONE" -> 1
            "TWO" -> 2
            "THREE" -> 3
            "FOUR" -> 4
            "FIVE" -> 5
            else -> 3
        }
    }
}
