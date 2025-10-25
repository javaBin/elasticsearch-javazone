# JavaZone Elasticsearch Integration

Complete Elasticsearch integration for JavaZone - all in one repository!

## 🎯 What This Deploys

**AWS (via Terraform):**
- SQS queues (main + DLQ)
- webhook-receiver Lambda (API Gateway)
- es-indexer-worker Lambda (SQS triggered)

**Coolify (manual):**
- Elasticsearch 8.11.0

**Cost: ~$2-5/month AWS + $0 Coolify = ~$2-5/month total**

---

## 🚀 Quick Start

### 1. Deploy Elasticsearch on Coolify

1. Coolify → New Resource → Docker Image
2. Image: `elasticsearch:8.11.0`
3. Environment:
   ```
   discovery.type=single-node
   xpack.security.enabled=true
   ELASTIC_PASSWORD=bi75Xtl3KPXI4CS7QRU8TrFRpF3mV1qX
   ES_JAVA_OPTS=-Xms1g -Xmx1g
   ```
4. Volume: `/data/elasticsearch` → `/usr/share/elasticsearch/data`
5. Port: `9200`
6. Deploy

7. Create index:
   ```bash
   curl -X PUT "http://your-es-url:9200/javazone_talks" \
     -u elastic:bi75Xtl3KPXI4CS7QRU8TrFRpF3mV1qX \
     -H "Content-Type: application/json" \
     -d @config/index-mapping.json
   ```

8. Update GitHub secret with your ES URL:
   ```bash
   gh secret set ELASTICSEARCH_URL --body "http://your-elasticsearch-domain:9200"
   ```

---

### 2. Deploy AWS Infrastructure (GitHub Actions)

Push to `main` or manually trigger workflow:

https://github.com/javaBin/elasticsearch-javazone/actions

Deploys: SQS + 2 Lambdas (~2 minutes)

---

### 3. Configure Moresleep

Use webhook URL from GitHub Actions output:

```properties
WEBHOOK_ENABLED=true
WEBHOOK_ENDPOINT=<url-from-output>
WEBHOOK_SECRET=7faa5e7879e189dfdeab497f647a88e15abcd7be4c2209f318465e764547d258
```

Redeploy moresleep.

---

## ✅ Testing

Create a talk → Check ES within 10 seconds:
```bash
curl -u elastic:pass "http://your-es-url:9200/javazone_talks/_search?q=test"
```

---

**Total setup time: ~10 minutes**
**Monthly cost: ~$2-5**

Perfect! 🎉
