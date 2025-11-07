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
