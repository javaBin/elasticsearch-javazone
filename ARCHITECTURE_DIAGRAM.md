# JavaZone Elasticsearch Integration - Architecture Diagrams

## System Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         JavaZone System                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌──────────────┐        ┌──────────────┐       ┌──────────────┐       │
│  │ submitthe-   │        │   cake-      │       │    libum     │       │
│  │ third        │───────→│   redux      │       │  (new UI)    │       │
│  │ (submit UI)  │ talks  │   (admin)    │       │              │       │
│  └──────────────┘        └──────┬───────┘       └──────┬───────┘       │
│                                  │                      │                │
│                                  ↓                      ↓                │
│                          ┌────────────────┐    ┌────────────────┐      │
│                          │   moresleep    │    │ Elasticsearch  │      │
│                          │   PostgreSQL   │    │  (search data) │      │
│                          │  (source of    │    │                │      │
│                          │   truth)       │    │                │      │
│                          └────────────────┘    └────────────────┘      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Detailed Event Flow

### 1. Talk Creation Flow

```
┌─────────┐
│ Speaker │ Creates talk
└────┬────┘
     │
     ↓
┌──────────────────┐
│ submitthethird   │ POST /data/conference/{id}/session
│ (Frontend)       │
└────┬─────────────┘
     │
     ↓
┌──────────────────────────────────────────────────────────────────┐
│ moresleep                                                         │
│                                                                   │
│  CreateNewSession.execute():                                     │
│  1. Validate input                                               │
│  2. INSERT INTO talk (...) VALUES (...)                          │
│  3. INSERT INTO speaker (...) VALUES (...)                       │
│  4. TalkRepo.registerTalkUpdate()                                │
│  5. 💫 WebhookService.emitTalkEvent("talk.created", ...)        │
│                                                                   │
└────┬──────────────────────────────────────────────────────────────┘
     │ Async (Thread Pool)
     │
     ↓
┌──────────────────────────────────────────────────────────────────┐
│ WebhookService                                                    │
│                                                                   │
│  1. Build event JSON:                                            │
│     {                                                             │
│       "eventId": "uuid",                                          │
│       "eventType": "talk.created",                               │
│       "entityId": "talk-123",                                    │
│       "conferenceId": "javazone-2024"                            │
│     }                                                             │
│  2. Generate HMAC-SHA256 signature                               │
│  3. HTTP POST to webhook-receiver                                │
│  4. Retry 3 times if failed                                      │
│                                                                   │
└────┬──────────────────────────────────────────────────────────────┘
     │ HTTP POST (< 50ms)
     │ Headers:
     │   X-Webhook-Signature: abc123...
     │   X-Event-Type: talk.created
     │   X-Event-Id: uuid
     │
     ↓
┌──────────────────────────────────────────────────────────────────┐
│ webhook-receiver (Ktor Service)                                  │
│                                                                   │
│  POST /webhook:                                                  │
│  1. Verify HMAC signature ✓                                      │
│  2. Parse event JSON                                             │
│  3. sqsClient.sendMessage(queueUrl, body)                        │
│  4. Return 200 OK                                                │
│                                                                   │
└────┬──────────────────────────────────────────────────────────────┘
     │ AWS SDK
     │
     ↓
┌──────────────────────────────────────────────────────────────────┐
│ AWS SQS Queue                                                     │
│                                                                   │
│  Message stored with:                                            │
│  - Body: event JSON                                              │
│  - Attributes: eventType, eventId                                │
│  - Retention: 4 days                                             │
│  - Visibility timeout: 30s                                       │
│  - Max receive count: 3 → DLQ                                    │
│                                                                   │
└────┬──────────────────────────────────────────────────────────────┘
     │ Long polling (20s wait)
     │ 5-10 second intervals
     │
     ↓
┌──────────────────────────────────────────────────────────────────┐
│ es-indexer-worker                                                │
│                                                                   │
│  Poll loop:                                                      │
│  1. sqsClient.receiveMessage(maxMessages=10)                     │
│  2. For each message:                                            │
│     a) Parse event JSON                                          │
│     b) eventType = "talk.created"                                │
│     c) entityId = "talk-123"                                     │
│                                                                   │
└────┬──────────────────────────────────────────────────────────────┘
     │ HTTP GET
     │
     ↓
┌──────────────────────────────────────────────────────────────────┐
│ moresleep API                                                     │
│                                                                   │
│  GET /data/session/talk-123                                      │
│                                                                   │
│  Returns complete talk JSON:                                     │
│  {                                                                │
│    "id": "talk-123",                                             │
│    "conferenceid": "javazone-2024",                              │
│    "status": "SUBMITTED",                                        │
│    "data": {                                                      │
│      "title": {"value": "My Talk", "privateData": false},       │
│      "abstract": {"value": "...", "privateData": false},         │
│      "pkomfeedbacks": {                                          │
│        "value": [                                                │
│          {"type": "comment", "author": "john", "comment": ".."},│
│          {"type": "rating", "author": "jane", "rating": "FOUR"} │
│        ],                                                         │
│        "privateData": true                                       │
│      }                                                            │
│    },                                                             │
│    "speakers": [...]                                             │
│  }                                                                │
│                                                                   │
└────┬──────────────────────────────────────────────────────────────┘
     │
     ↓
┌──────────────────────────────────────────────────────────────────┐
│ es-indexer-worker (continued)                                    │
│                                                                   │
│  3. Transform talk JSON:                                         │
│     - Extract pkomfeedbacks.value array                          │
│     - Split into comments[] and ratings[]                        │
│     - Calculate avgRating                                        │
│     - Denormalize speakers                                       │
│     - Extract tags, keywords                                     │
│     - Build ES document:                                         │
│       {                                                           │
│         "talkId": "talk-123",                                    │
│         "title": "My Talk",                                      │
│         "abstract": "...",                                       │
│         "status": "SUBMITTED",                                   │
│         "speakers": [...],                                       │
│         "comments": [                                            │
│           {"author": "john", "comment": "...", "created": "..."} │
│         ],                                                        │
│         "ratings": [                                             │
│           {"author": "jane", "rating": "FOUR"}                   │
│         ],                                                        │
│         "avgRating": 4.0,                                        │
│         "indexed_at": "2025-10-25T12:00:00"                      │
│       }                                                           │
│                                                                   │
└────┬──────────────────────────────────────────────────────────────┘
     │ ES REST API
     │
     ↓
┌──────────────────────────────────────────────────────────────────┐
│ Elasticsearch                                                     │
│                                                                   │
│  PUT /javazone_talks/_doc/talk-123                               │
│  {                                                                │
│    ... (ES document) ...                                         │
│  }                                                                │
│                                                                   │
│  Result: Document indexed successfully                           │
│                                                                   │
└────┬──────────────────────────────────────────────────────────────┘
     │
     ↓
┌──────────────────────────────────────────────────────────────────┐
│ es-indexer-worker (continued)                                    │
│                                                                   │
│  4. sqsClient.deleteMessage(receiptHandle)                       │
│     → Message removed from queue (success!)                      │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘

⏱️ Total time: ~5-15 seconds (depending on polling interval)
```

## Data Flow: Comments & Ratings

```
┌─────────────────────────────────────────────────────────────────┐
│ Discovery: Comments/Ratings are ALREADY in moresleep DB!       │
└─────────────────────────────────────────────────────────────────┘

┌──────────────┐
│ cake-redux   │ User adds comment via UI
└──────┬───────┘
       │
       ↓
┌─────────────────────────────────────────────────────────────────┐
│ FeedbackInSleepingpill.addFeedback()                            │
│                                                                  │
│ 1. Fetch current pkomfeedbacks from moresleep API               │
│ 2. Append new comment to array                                  │
│ 3. PUT /data/session/{id} with updated pkomfeedbacks            │
│                                                                  │
└──────┬──────────────────────────────────────────────────────────┘
       │
       ↓
┌─────────────────────────────────────────────────────────────────┐
│ moresleep - UpdateSession.execute()                             │
│                                                                  │
│ 1. UPDATE talk SET data = {...} WHERE id = 'talk-123'          │
│    (data JSON now includes new comment in pkomfeedbacks)        │
│ 2. 💫 WebhookService.emitTalkEvent("talk.updated", ...)        │
│                                                                  │
└──────┬──────────────────────────────────────────────────────────┘
       │
       ↓
┌─────────────────────────────────────────────────────────────────┐
│ Webhook → SQS → Worker → Fetch latest → Index to ES             │
│                                                                  │
│ ES document now includes:                                       │
│ {                                                                │
│   "comments": [                                                  │
│     {"author": "john", "comment": "Great talk!", ...},          │
│     {"author": "jane", "comment": "Love it!", ...}              │
│   ]                                                              │
│ }                                                                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Failure Handling

```
┌─────────────────────────────────────────────────────────────────┐
│ Scenario: Elasticsearch is Down                                 │
└─────────────────────────────────────────────────────────────────┘

Message arrives in SQS
  │
  ↓
Worker polls message
  │
  ↓
Worker fetches talk from moresleep ✓
  │
  ↓
Worker tries to index to ES ✗ (Connection refused)
  │
  ↓
Worker throws exception (doesn't delete message)
  │
  ↓
SQS: Message visibility timeout expires (30s)
  │
  ↓
Message becomes visible again in queue
  │
  ↓
Worker polls message again (Attempt 2)
  │
  ↓
... (repeat up to 3 times)
  │
  ↓
After 3 failed attempts:
  │
  ↓
SQS moves message to Dead Letter Queue (DLQ)
  │
  ↓
Admin receives alert 🚨
  │
  ↓
Admin fixes Elasticsearch
  │
  ↓
Admin manually retries DLQ messages
  │
  ↓
Messages processed successfully ✓
```

## Deployment Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                         AWS hosted.                            │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  ┌──────────────┐   Internal Network   ┌──────────────┐        │
│  │  moresleep   │◄─────────────────────│ webhook-     │        │
│  │  :8082       │                      │ receiver     │        │
│  └──────┬───────┘                      │ :8083        │        │
│         │                              └──────┬───────┘        │
│         │                                     │                │
│         │ PostgreSQL                          │ AWS SQS        │
│         │ connection                          │ (Internet)     │
│         ↓                                     ↓                │
│  ┌──────────────┐                                              │
│  │ PostgreSQL   │                         ┌──────────┐         │
│  │ :5432        │                         │ AWS SQS  │         │
│  └──────────────┘                         │  Queue   │         │
│                                           └────┬─────┘         │
│  ┌──────────────┐                              │               │
│  │es-indexer-   │◄─────────────────────────────┘               │
│  │worker        │                                              │
│  │(polls SQS)   │                                              │
│  └──────┬───────┘                          ┌──────────┐        │
│         │          ─────────────────────-> │ AWS SQS. │        │
│         │                                  │  Queue   │        │
│         │                                  └────┬─────┘        │
│         │                                  ┌──────────┐        │
│         │                                  │ Lambda   │        │
│         │                                  │          │        │
│         ↓                                  └────┬─────┘        │
│  ┌──────────────┐                           Alt annet          │
│  │Elasticsearch │                                              │
│  │ :9200        │                                              │
│  └──────────────┘                                              │
│                                                                │
└────────────────────────────────────────────────────────────────┘

All services communicate via internal Docker network except AWS SQS
```

## Service Responsibilities

```
┌────────────────────┬──────────────────────────────────────────┐
│ Service            │ Responsibility                            │
├────────────────────┼──────────────────────────────────────────┤
│ moresleep          │ - Source of truth (PostgreSQL)           │
│                    │ - Emit webhook events                     │
│                    │ - Provide GET API for fresh data         │
├────────────────────┼──────────────────────────────────────────┤
│ webhook-receiver   │ - Validate HMAC signatures               │
│                    │ - Queue messages to SQS (fast!)          │
│                    │ - Return 200 OK immediately              │
├────────────────────┼──────────────────────────────────────────┤
│ AWS SQS            │ - Durable message storage                │
│                    │ - Automatic retry logic                  │
│                    │ - Dead letter queue for failures         │
│                    │ - Decouple producers/consumers           │
├────────────────────┼──────────────────────────────────────────┤
│ es-indexer-worker  │ - Poll SQS for messages                  │
│                    │ - Fetch fresh data from moresleep        │
│                    │ - Transform to ES format                 │
│                    │ - Index to Elasticsearch                 │
│                    │ - Delete SQS message on success          │
│                    │ - Bulk reindex on startup (optional)     │
├────────────────────┼──────────────────────────────────────────┤
│ Elasticsearch      │ - Store denormalized talk documents      │
│                    │ - Provide search capabilities            │
│                    │ - Support filtering, aggregations        │
└────────────────────┴──────────────────────────────────────────┘
```

---

## Key Insights

### Why Fetch-on-Index?
- **Always current**: ES gets latest data, not stale webhook payload
- **Includes latest comments/ratings**: Always fresh from DB
- **Handles concurrent updates**: No race conditions

### Why SQS?
- **Reliability**: Messages never lost
- **Decoupling**: Services can restart independently
- **Scalability**: Multiple workers can process queue
- **Built-in retry**: No custom retry logic needed

### Why Separate Receiver?
- **Fast webhook response**: < 50ms to return 200 OK
- **Extensibility**: Other services can subscribe to queue
- **Separation of concerns**: Receiving ≠ Processing
- **Independent scaling**: Scale receiver and worker separately
