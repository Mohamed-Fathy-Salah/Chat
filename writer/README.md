# Writer Service

Go-based async worker service for processing chat and message operations.

## Architecture

```
writer/
├── main.go                      # Entry point
├── internal/
│   ├── config/
│   │   └── config.go           # Configuration management
│   ├── database/
│   │   ├── database.go         # MySQL connection
│   │   └── redis.go            # Redis connection
│   ├── models/
│   │   └── models.go           # Data models
│   ├── handlers/
│   │   ├── chat.go             # Chat operations
│   │   └── message.go          # Message operations
│   ├── queue/
│   │   ├── rabbitmq.go         # RabbitMQ client
│   │   ├── chat_consumer.go   # Chat queue consumer
│   │   └── message_consumer.go # Message queue consumers
│   └── cron/
│       └── count_sync.go       # Count synchronization job
├── go.mod
├── go.sum
└── Dockerfile
```

## Components

### Consumers
- **Chat Consumer**: Processes `create_chats` queue
- **Message Create Consumer**: Processes `create_messages` queue  
- **Message Update Consumer**: Processes `update_messages` queue

### Cron Job
- **Count Sync**: Runs every 10 seconds to sync counts from Redis to MySQL
  - Syncs `chats_count` for applications
  - Syncs `messages_count` for chats

### Handlers
- **ChatHandler**: Handles chat creation logic
- **MessageHandler**: Handles message create/update logic

## Design Principles

1. **Separation of Concerns**: Each package has a single responsibility
2. **Dependency Injection**: Dependencies passed through constructors
3. **No Direct Count Updates**: Counts only updated by cron job
4. **Error Handling**: Proper error handling with message requeuing
5. **Graceful Shutdown**: Handles SIGINT/SIGTERM signals

## Environment Variables

- `DATABASE_HOST`: MySQL host (default: db)
- `DATABASE_USERNAME`: MySQL username (default: root)
- `DATABASE_PASSWORD`: MySQL password (default: password)
- `DATABASE_NAME`: MySQL database name (default: auth_api_development)
- `REDIS_URL`: Redis connection URL (default: redis://redis:6379/0)
- `RABBITMQ_URL`: RabbitMQ connection URL (default: amqp://guest:guest@rabbitmq:5672/)

## Building

```bash
docker-compose build writer
```

## Running

```bash
docker-compose up writer
```

## Monitoring

View logs:
```bash
docker logs chat-writer-1 -f
```

## Testing

The service will automatically:
1. Connect to MySQL, Redis, and RabbitMQ
2. Start three queue consumers
3. Start the count sync cron job (every 10 seconds)
4. Log all processed messages

---

## Message Formats

### Chat Creation Message (create_chats queue)

```json
{
  "application_id": 123,
  "token": "app_abc123",
  "number": 1,
  "creator_id": 456
}
```

### Message Creation (create_messages queue)

```json
{
  "chat_id": 789,
  "token": "app_abc123",
  "chat_number": 1,
  "number": 1,
  "body": "Hello, world!",
  "creator_id": 456
}
```

### Message Update (update_messages queue)

```json
{
  "chat_id": 789,
  "token": "app_abc123",
  "chat_number": 1,
  "number": 1,
  "body": "Updated message text"
}
```

---

## Error Handling

The service implements robust error handling:

1. **Connection Errors**: Automatic reconnection with exponential backoff
2. **Message Processing Errors**: Failed messages are logged and not re-queued
3. **Database Errors**: Transactions rolled back, errors logged
4. **Elasticsearch Errors**: Logged but don't block message creation

---

## Performance Considerations

### Count Sync Optimization

The cron job runs every 10 seconds and:
- Scans Redis for all counter keys
- Batches updates to MySQL
- Only updates changed counters
- Minimal database locking

### Consumer Concurrency

Each consumer runs in its own goroutine:
- Non-blocking message processing
- Automatic prefetch optimization
- Fair distribution across instances

### Database Connection Pool

- Configurable max connections
- Automatic connection reuse
- Health checks via ping

---

## Graceful Shutdown

The service handles SIGINT/SIGTERM signals:

```go
// Shutdown sequence:
1. Stop accepting new messages
2. Finish processing current messages
3. Close RabbitMQ connections
4. Close database connections
5. Exit cleanly
```

To gracefully stop:
```bash
docker-compose stop writer
```

---

## Elasticsearch Integration

### Message Indexing

Messages are automatically indexed for search:
- Index name: `messages`
- Document ID: `<token>:<chat_number>:<message_number>`
- Searchable fields: `body`, `token`, `chat_number`

### Index Mapping

```json
{
  "mappings": {
    "properties": {
      "token": {"type": "keyword"},
      "chat_number": {"type": "integer"},
      "number": {"type": "integer"},
      "body": {"type": "text"},
      "created_at": {"type": "date"}
    }
  }
}
```

---

## Debugging

### Enable Verbose Logging

Modify `main.go` to add debug statements:
```go
log.Printf("DEBUG: Processing message: %+v", msg)
```

### Check RabbitMQ Queue Status

```bash
docker-compose exec rabbitmq rabbitmqctl list_queues
```

### Monitor Database Connections

```bash
docker-compose exec db mysql -u root -ppassword -e "SHOW PROCESSLIST;"
```

### Verify Elasticsearch Indexing

```bash
curl http://localhost:9200/messages/_search?pretty
```

---

## Configuration Options

### Environment Variables (Optional)

- `COUNT_SYNC_INTERVAL`: Cron job interval (default: 10s)
- `RABBITMQ_PREFETCH_COUNT`: Messages to prefetch per consumer (default: 1)
- `DB_MAX_OPEN_CONNS`: Maximum database connections (default: 10)
- `DB_MAX_IDLE_CONNS`: Maximum idle connections (default: 5)

### Scaling Workers

Run multiple writer instances for higher throughput:

```yaml
# docker-compose.yml
writer:
  # ... existing config ...
  deploy:
    replicas: 3
```

---

## Troubleshooting

### Messages not being processed

1. Check RabbitMQ connection:
   ```bash
   docker-compose logs writer | grep "Connected to RabbitMQ"
   ```

2. Verify queue exists:
   ```bash
   docker-compose exec rabbitmq rabbitmqctl list_queues
   ```

3. Check for errors in logs:
   ```bash
   docker-compose logs writer | grep ERROR
   ```

### Counts not syncing

1. Verify Redis keys exist:
   ```bash
   docker-compose exec redis redis-cli KEYS "*"
   ```

2. Check cron job logs:
   ```bash
   docker-compose logs writer | grep "Syncing counts"
   ```

3. Verify database connectivity:
   ```bash
   docker-compose exec writer go run -e "SELECT 1"
   ```

### High Memory Usage

- Reduce `RABBITMQ_PREFETCH_COUNT`
- Lower `DB_MAX_OPEN_CONNS`
- Add memory limits in docker-compose.yml

---

## Development

### Local Development

```bash
# Install dependencies
go mod download

# Run with live reload (install air)
go install github.com/cosmtrek/air@latest
air

# Build binary
go build -o writer main.go

# Run tests (if implemented)
go test ./...
```

### Code Structure Best Practices

- Keep handlers stateless
- Use dependency injection
- Log all errors with context
- Handle panics with recovery
- Use context for cancellation

---

## Future Enhancements

Potential improvements:
- [ ] Add retry logic for failed messages
- [ ] Implement dead letter queue
- [ ] Add metrics (Prometheus/Grafana)
- [ ] Unit and integration tests
- [ ] Distributed tracing (Jaeger)
- [ ] Configuration via config file
- [ ] Health check HTTP endpoint

---

## Contributing

When contributing:
1. Follow Go best practices
2. Add error handling for all operations
3. Log important events
4. Test with docker-compose
5. Update this README for new features
