# Requests Service

The Requests Service handles all API requests for the chat application, providing endpoints for managing applications, chats, and messages.

## Features

- **Application Management**: Create, update, and list applications
- **Chat Management**: Create and list chats within applications
- **Message Management**: Create, update, list, and search messages within chats
- **Authentication**: JWT-based authentication with cookie storage
- **Redis Integration**: Counter management for chat and message numbering
- **RabbitMQ Integration**: Asynchronous message queue for data persistence
- **Eventual Consistency**: Background jobs to update counts

## API Documentation

**Swagger UI**: Interactive API documentation available at `http://localhost:3000/api-docs/index.html`

## API Endpoints

### Authentication

- `POST /api/v1/auth/register` - Register a new user
- `POST /api/v1/auth/login` - Login user
- `DELETE /api/v1/auth/logout` - Logout user
- `GET /api/v1/auth/me` - Get current user
- `POST /api/v1/auth/refresh` - Refresh auth token

### Applications

| Method | Route | Description | Response |
|--------|-------|-------------|----------|
| POST | `/api/v1/applications` | Create application | `{ "token": "string" }` |
| PUT | `/api/v1/applications` | Update application | Status 200/403/404 |
| GET | `/api/v1/applications` | List all applications | Array of applications |

### Chats

| Method | Route | Description | Response |
|--------|-------|-------------|----------|
| POST | `/api/v1/applications/:token/chats` | Create chat | `{ "chatNumber": number }` |
| GET | `/api/v1/applications/:token/chats` | List chats | Array of chats |

### Messages

| Method | Route | Description | Response |
|--------|-------|-------------|----------|
| POST | `/api/v1/applications/:token/chats/:chat_number/messages` | Create message | `{ "messageNumber": number }` |
| PUT | `/api/v1/applications/:token/chats/:chat_number/messages` | Update message | Status 200/403/404 |
| GET | `/api/v1/applications/:token/chats/:chat_number/messages` | List messages | Array of messages |
| GET | `/api/v1/applications/:token/chats/:chat_number/messages/search?q=query` | Search messages | Array of messages |

## Setup

### Prerequisites

- Ruby 3.2.0
- MySQL
- Redis
- RabbitMQ

### Installation

1. Install dependencies:
```bash
bundle install
```

2. Setup database:
```bash
rails db:create db:migrate
```

3. Start the server:
```bash
rails server
```

## Background Jobs

The service publishes messages to RabbitMQ queues for asynchronous processing by the Writer Service. No background jobs or cron tasks run in the Requests Service itself.

**Note:** Count updates (chats_count and messages_count) are handled by the Writer Service's cron job, not by the Requests Service.

## Testing

Run the test suite:

```bash
bundle exec rspec
```

### Test Coverage

The test suite includes comprehensive coverage for:

**Model Tests:**
- User authentication and validation
- Application token generation and uniqueness
- Chat and Message associations
- Edge cases and data integrity
- Dependent record cascading

**Request/Integration Tests:**
- Authentication flows (register, login, logout, token refresh)
- Application CRUD operations
- Chat creation and listing
- Message CRUD and search operations
- Error handling (401, 403, 404, 422)
- Authorization and access control
- Pagination and filtering
- Redis counter operations
- RabbitMQ message publishing

**Service Tests:**
- JWT encoding/decoding and secret key rotation
- Message search (Elasticsearch and SQL fallback)
- RabbitMQ connection and publishing
- Error handling and graceful degradation

**Total Test Files:** 16  
**Test Lines:** 1,725+ lines of test code

### Running Specific Tests

```bash
# Run only model tests
bundle exec rspec spec/models

# Run only request tests
bundle exec rspec spec/requests

# Run only service tests
bundle exec rspec spec/services

# Run a specific test file
bundle exec rspec spec/services/message_search_service_spec.rb

# Run tests with documentation format
bundle exec rspec --format documentation
```

## Environment Variables

- `DATABASE_HOST` - MySQL database host
- `DATABASE_USERNAME` - MySQL username
- `DATABASE_PASSWORD` - MySQL password
- `REDIS_URL` - Redis connection URL
- `RABBITMQ_URL` - RabbitMQ connection URL
- `RAILS_ENV` - Rails environment (development/production/test)

## Architecture

The service uses:
- **MySQL**: Primary data store
- **Redis**: Counter management for auto-incrementing chat and message numbers
- **RabbitMQ**: Message queue for asynchronous processing
- **Background Processing**: Asynchronous operations via RabbitMQ (handled by Writer Service)

## License

MIT

---

## Project Structure

```
requests/
├── app/
│   ├── controllers/
│   │   └── api/v1/          # API controllers
│   ├── models/              # ActiveRecord models
│   ├── services/            # Business logic services
│   └── lib/                 # Custom libraries
├── config/
│   ├── routes.rb            # API routes
│   └── database.yml         # Database configuration
├── db/
│   ├── migrate/             # Database migrations
│   └── schema.rb            # Database schema
├── spec/                    # RSpec tests
│   ├── models/
│   ├── requests/
│   └── services/
└── Dockerfile
```

## Key Components

### Models
- **User**: Authentication and user management
- **Application**: Top-level tenant with unique token
- **Chat**: Conversations within applications
- **Message**: Individual messages within chats

### Services
- **TokenGenerator**: Generates unique application tokens
- **RedisCounterService**: Manages auto-incrementing counters
- **RabbitMQPublisher**: Publishes messages to queues
- **ElasticsearchService**: Handles message indexing and search

### Controllers
- **AuthController**: User registration, login, logout
- **ApplicationsController**: CRUD operations for applications
- **ChatsController**: Create and list chats
- **MessagesController**: CRUD operations and search for messages

## Database Migrations

View current schema:
```bash
rails db:schema:dump
```

Create new migration:
```bash
rails generate migration AddColumnToTable column:type
```

## RabbitMQ Queues

The service publishes to three queues:
- `create_chats`: New chat creation events
- `create_messages`: New message creation events
- `update_messages`: Message update events

## Redis Keys

- `<application_token>`: Chat counter for application
- `<application_token>:<chat_number>`: Message counter for chat

## Caching Strategy

- Application lookups cached by token
- Chat lookups cached by application + number
- Message search results from Elasticsearch (not cached)

## Performance Tips

1. Use pagination for message lists (`?page=1&limit=20`)
2. Search is powered by Elasticsearch for fast full-text queries
3. Counters are eventually consistent (updated by writer service)
4. Database connections pooled via Rails connection pool

## Development Tips

### Interactive Console

```bash
docker-compose exec requests rails console
```

### Database Console

```bash
docker-compose exec requests rails dbconsole
```

### Route Inspection

```bash
rails routes | grep api/v1
```

## Common Rake Tasks

```bash
# Database operations
rake db:create db:migrate
rake db:seed

# Run tests
bundle exec rspec

# Check routes
rake routes
```
