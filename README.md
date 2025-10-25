# Elasticsearch for JavaZone

Elasticsearch deployment on AWS Fargate with EFS persistent storage.

## Architecture

- **Single Fargate task** running Elasticsearch 8.11
- **EFS volume** for persistent data storage
- **Service Discovery** for stable DNS: `elasticsearch.javazone.internal:9200`
- **1 vCPU, 2GB RAM** (sufficient for ~10K talks)

## Deployment

### 1. Deploy Infrastructure

```bash
cd terraform

cp terraform.tfvars.example terraform.tfvars
# Edit with your values

terraform init
terraform apply
```

**What this creates:**
- ECS Cluster and Fargate task
- EFS file system for data persistence
- Security groups
- Service discovery (optional DNS name)
- SSM parameter for password

**Cost:** ~$35-45/month (Fargate + EFS)

### 2. Wait for Elasticsearch to Start

```bash
# Check task status
aws ecs list-tasks --cluster elasticsearch-javazone --region eu-central-1

# Get task IP (if not using service discovery)
aws ecs describe-tasks \
  --cluster elasticsearch-javazone \
  --tasks <task-arn> \
  --region eu-central-1 | grep "privateIpv4Address"
```

### 3. Create Index

If using service discovery:
```bash
ES_URL="http://elasticsearch.javazone.internal:9200"
```

Otherwise:
```bash
ES_URL="http://<task-private-ip>:9200"
```

Create the index:
```bash
curl -X PUT "$ES_URL/javazone_talks" \
  -u elastic:<your-password> \
  -H "Content-Type: application/json" \
  -d @../config/index-mapping.json
```

Verify:
```bash
curl -u elastic:<password> "$ES_URL/javazone_talks"
curl -u elastic:<password> "$ES_URL/_cluster/health"
```

## Access from Other Services

### With Service Discovery (Recommended)
```
ELASTICSEARCH_URL=http://elasticsearch.javazone.internal:9200
```

Use this in:
- es-indexer-worker terraform.tfvars
- libum configuration

### Without Service Discovery
Use the task's private IP (changes on restart):
```
ELASTICSEARCH_URL=http://10.0.x.x:9200
```

## Monitoring

View task logs in AWS ECS Console:
- ECS → Clusters → elasticsearch-javazone → Tasks → View logs tab

Check cluster health:
```bash
curl -u elastic:<password> "$ES_URL/_cluster/health"
```

Check document count:
```bash
curl -u elastic:<password> "$ES_URL/javazone_talks/_count"
```

## Data Persistence

Data is stored on EFS and persists across task restarts. To completely reset:

```bash
# Stop service
aws ecs update-service \
  --cluster elasticsearch-javazone \
  --service elasticsearch-javazone \
  --desired-count 0

# Delete EFS data (requires EC2 instance or Fargate task with EFS mounted)
# Then restart service
aws ecs update-service \
  --cluster elasticsearch-javazone \
  --service elasticsearch-javazone \
  --desired-count 1
```

## Cost Estimate

- **Fargate**: ~$25-30/month (1 vCPU, 2GB, always running)
- **EFS**: ~$10-15/month (5-10GB data)
- **SSM**: Free
- **Service Discovery**: Free

**Total: ~$35-45/month**

## Scaling

For higher load (unlikely needed):
- Increase `task_cpu` and `task_memory` in terraform.tfvars
- Apply and restart

For production HA:
- Deploy multiple tasks
- Use Application Load Balancer
- Multiple AZ deployment

But for 10K talks, single task is sufficient.

## Backup

EFS data is persistent, but consider:
- EFS automatic backups (AWS Backup)
- Elasticsearch snapshot repository
- Periodic manual snapshots

## Sample Queries

See `config/sample-queries.sh` for common Elasticsearch queries.
