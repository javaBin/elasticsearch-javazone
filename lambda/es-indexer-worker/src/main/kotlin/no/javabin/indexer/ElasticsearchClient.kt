package no.javabin.indexer

import org.apache.http.HttpHost
import org.apache.http.auth.AuthScope
import org.apache.http.auth.UsernamePasswordCredentials
import org.apache.http.impl.client.BasicCredentialsProvider
import org.elasticsearch.action.index.IndexRequest
import org.elasticsearch.action.update.UpdateRequest
import org.elasticsearch.client.RequestOptions
import org.elasticsearch.client.RestClient
import org.elasticsearch.client.RestHighLevelClient
import org.elasticsearch.xcontent.XContentType
import org.slf4j.LoggerFactory
import java.net.URI

class ElasticsearchClient {
    private val logger = LoggerFactory.getLogger(ElasticsearchClient::class.java)
    private val client: RestHighLevelClient
    private val index = System.getenv("ELASTICSEARCH_INDEX")
        ?: throw IllegalStateException("ELASTICSEARCH_INDEX not set")

    init {
        val esUrl = System.getenv("ELASTICSEARCH_URL")
            ?: throw IllegalStateException("ELASTICSEARCH_URL not set")
        val username = System.getenv("ELASTICSEARCH_USERNAME") ?: "elastic"
        val password = System.getenv("ELASTICSEARCH_PASSWORD")
            ?: throw IllegalStateException("ELASTICSEARCH_PASSWORD not set")

        val uri = URI(esUrl)

        val credentialsProvider = BasicCredentialsProvider().apply {
            setCredentials(AuthScope.ANY, UsernamePasswordCredentials(username, password))
        }

        client = RestHighLevelClient(
            RestClient.builder(HttpHost(uri.host, uri.port, uri.scheme))
                .setHttpClientConfigCallback { httpClientBuilder ->
                    httpClientBuilder.setDefaultCredentialsProvider(credentialsProvider)
                }
        )

        logger.info("Elasticsearch client initialized: $esUrl (index: $index)")
    }

    fun indexDocument(id: String, document: String) {
        val request = IndexRequest(index)
            .id(id)
            .source(document, XContentType.JSON)

        val response = client.index(request, RequestOptions.DEFAULT)
        logger.debug("Indexed document $id: result=${response.result}")
    }

    fun updateDocument(id: String, fields: Map<String, Any>) {
        val request = UpdateRequest(index, id)
            .doc(fields)

        client.update(request, RequestOptions.DEFAULT)
        logger.debug("Updated document $id with fields: $fields")
    }

    fun close() {
        client.close()
    }
}
