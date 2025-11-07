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

### Count Update Cron Job

Run the following rake task to update chats_count and messages_count from Redis:

```bash
rake counts:update
```

This should be scheduled to run periodically (e.g., every 5 minutes) using cron or a job scheduler.

## Testing

Run the test suite:

```bash
bundle exec rspec
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
- **Background Jobs**: Periodic updates for eventual consistency

## License

MIT
