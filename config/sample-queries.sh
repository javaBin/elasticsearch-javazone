#!/bin/bash
# Sample Elasticsearch queries for JavaZone talks

# Set these variables
ES_URL="http://elasticsearch.javazone.internal:9200"
ES_USER="elastic"
ES_PASS="your-password"

# Search by title
echo "=== Search for 'kotlin' in title ==="
curl -u $ES_USER:$ES_PASS "$ES_URL/javazone_talks/_search" \
  -H "Content-Type: application/json" -d '{
  "query": {
    "match": {"title": "kotlin"}
  }
}' | jq

# Filter by status
echo "=== Get all SUBMITTED talks ==="
curl -u $ES_USER:$ES_PASS "$ES_URL/javazone_talks/_search" \
  -H "Content-Type: application/json" -d '{
  "query": {
    "term": {"status": "SUBMITTED"}
  },
  "size": 100
}' | jq

# Search by speaker name
echo "=== Search for speaker ==="
curl -u $ES_USER:$ES_PASS "$ES_URL/javazone_talks/_search" \
  -H "Content-Type: application/json" -d '{
  "query": {
    "nested": {
      "path": "speakers",
      "query": {
        "match": {"speakers.name": "john"}
      }
    }
  }
}' | jq

# Filter by tag
echo "=== Get talks with specific tag ==="
curl -u $ES_USER:$ES_PASS "$ES_URL/javazone_talks/_search" \
  -H "Content-Type: application/json" -d '{
  "query": {
    "nested": {
      "path": "tags",
      "query": {
        "term": {"tags.tag": "java"}
      }
    }
  }
}' | jq

# High rated talks
echo "=== Get talks with avg rating > 4 ==="
curl -u $ES_USER:$ES_PASS "$ES_URL/javazone_talks/_search" \
  -H "Content-Type: application/json" -d '{
  "query": {
    "range": {
      "avgRating": {"gte": 4.0}
    }
  }
}' | jq

# Complex query: Java talks, submitted, with comments
echo "=== Complex query ==="
curl -u $ES_USER:$ES_PASS "$ES_URL/javazone_talks/_search" \
  -H "Content-Type: application/json" -d '{
  "query": {
    "bool": {
      "must": [
        {"match": {"title": "java"}},
        {"term": {"status": "SUBMITTED"}}
      ],
      "filter": {
        "nested": {
          "path": "comments",
          "query": {"exists": {"field": "comments"}}
        }
      }
    }
  }
}' | jq

# Aggregations: Count by status
echo "=== Count talks by status ==="
curl -u $ES_USER:$ES_PASS "$ES_URL/javazone_talks/_search" \
  -H "Content-Type: application/json" -d '{
  "size": 0,
  "aggs": {
    "by_status": {
      "terms": {"field": "status"}
    }
  }
}' | jq

# Count by conference
echo "=== Count talks by conference ==="
curl -u $ES_USER:$ES_PASS "$ES_URL/javazone_talks/_search" \
  -H "Content-Type: application/json" -d '{
  "size": 0,
  "aggs": {
    "by_conference": {
      "terms": {"field": "conferenceId"}
    }
  }
}' | jq
