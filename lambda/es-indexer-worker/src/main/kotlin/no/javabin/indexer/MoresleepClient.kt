package no.javabin.indexer

import org.jsonbuddy.JsonObject
import org.jsonbuddy.parse.JsonParser
import java.net.HttpURLConnection
import java.net.URL
import java.util.Base64

class MoresleepClient {
    private val baseUrl = System.getenv("MORESLEEP_API_URL")
        ?: throw IllegalStateException("MORESLEEP_API_URL not set")
    private val username = System.getenv("MORESLEEP_USERNAME") ?: ""
    private val password = System.getenv("MORESLEEP_PASSWORD") ?: ""

    fun fetchTalk(talkId: String): JsonObject {
        val url = URL("$baseUrl/data/session/$talkId")
        val connection = url.openConnection() as HttpURLConnection

        connection.requestMethod = "GET"
        if (username.isNotEmpty() && password.isNotEmpty()) {
            connection.setRequestProperty("Authorization", basicAuth(username, password))
        }
        connection.connectTimeout = 10000
        connection.readTimeout = 10000

        if (connection.responseCode != 200) {
            val errorBody = connection.errorStream?.bufferedReader()?.readText() ?: "No error body"
            throw RuntimeException("Failed to fetch talk $talkId: HTTP ${connection.responseCode} - $errorBody")
        }

        return JsonParser.parseToObject(connection.inputStream)
    }

    fun fetchAllTalksForConference(conferenceId: String): List<JsonObject> {
        val url = URL("$baseUrl/data/conference/$conferenceId/session")
        val connection = url.openConnection() as HttpURLConnection

        connection.requestMethod = "GET"
        if (username.isNotEmpty() && password.isNotEmpty()) {
            connection.setRequestProperty("Authorization", basicAuth(username, password))
        }
        connection.connectTimeout = 30000
        connection.readTimeout = 30000

        if (connection.responseCode != 200) {
            throw RuntimeException("Failed to fetch talks for conference $conferenceId: HTTP ${connection.responseCode}")
        }

        val response = JsonParser.parseToObject(connection.inputStream)
        return response.requiredArray("sessions").objectStream().toList()
    }

    private fun basicAuth(user: String, pass: String): String {
        val credentials = "$user:$pass"
        val encoded = Base64.getEncoder().encodeToString(credentials.toByteArray())
        return "Basic $encoded"
    }
}
