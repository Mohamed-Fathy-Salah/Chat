package queue

import (
	"context"
	"encoding/json"
	"log"

	"github.com/chat/writer/internal/handlers"
	"github.com/chat/writer/internal/models"
)

type MessageConsumer struct {
	rabbit         *RabbitMQ
	messageHandler *handlers.MessageHandler
	retryHandler   *RetryHandler
}

func NewMessageConsumer(rabbit *RabbitMQ, messageHandler *handlers.MessageHandler) *MessageConsumer {
	return &MessageConsumer{
		rabbit:         rabbit,
		messageHandler: messageHandler,
		retryHandler:   NewRetryHandler(),
	}
}

func (c *MessageConsumer) StartCreateConsumer(ctx context.Context) {
	ch, err := c.rabbit.CreateChannel()
	if err != nil {
		log.Fatalf("Failed to open channel: %v", err)
	}
	defer ch.Close()

	queueName := "create_messages"
	q, err := c.rabbit.DeclareQueueWithDLQ(ch, queueName)
	if err != nil {
		log.Fatalf("Failed to declare queue with DLQ: %v", err)
	}

	msgs, err := c.rabbit.Consume(ch, q.Name)
	if err != nil {
		log.Fatalf("Failed to register consumer: %v", err)
	}

	log.Println("Waiting for create_messages messages...")

	for {
		select {
		case <-ctx.Done():
			log.Println("MessageConsumer (create): Shutting down gracefully...")
			return
		case msg, ok := <-msgs:
			if !ok {
				log.Println("MessageConsumer (create): Channel closed")
				return
			}

			// Log retry metrics if this is a retry
			c.retryHandler.LogRetryMetrics(msg)

			var msgData models.CreateMessageMessage
			if err := json.Unmarshal(msg.Body, &msgData); err != nil {
				log.Printf("Error unmarshaling message: %v", err)
				// Parsing errors shouldn't be retried - send to DLQ
				msg.Nack(false, false)
				continue
			}

			if err := c.messageHandler.CreateMessage(msgData); err != nil {
				log.Printf("Error creating message: %v", err)
				// Use retry handler with exponential backoff
				if retryErr := c.retryHandler.HandleFailedMessage(ch, msg, queueName, err); retryErr != nil {
					log.Printf("Error handling retry: %v", retryErr)
					msg.Nack(false, false)
				}
			} else {
				msg.Ack(false)
				retryCount := c.retryHandler.GetRetryCount(msg)
				if retryCount > 0 {
					log.Printf("Successfully created message %d in chat %d after %d retries", 
						msgData.MessageNumber, msgData.ChatNumber, retryCount)
				} else {
					log.Printf("Created message %d in chat %d", msgData.MessageNumber, msgData.ChatNumber)
				}
			}
		}
	}
}

func (c *MessageConsumer) StartUpdateConsumer(ctx context.Context) {
	ch, err := c.rabbit.CreateChannel()
	if err != nil {
		log.Fatalf("Failed to open channel: %v", err)
	}
	defer ch.Close()

	queueName := "update_messages"
	q, err := c.rabbit.DeclareQueueWithDLQ(ch, queueName)
	if err != nil {
		log.Fatalf("Failed to declare queue with DLQ: %v", err)
	}

	msgs, err := c.rabbit.Consume(ch, q.Name)
	if err != nil {
		log.Fatalf("Failed to register consumer: %v", err)
	}

	log.Println("Waiting for update_messages messages...")

	for {
		select {
		case <-ctx.Done():
			log.Println("MessageConsumer (update): Shutting down gracefully...")
			return
		case msg, ok := <-msgs:
			if !ok {
				log.Println("MessageConsumer (update): Channel closed")
				return
			}

			// Log retry metrics if this is a retry
			c.retryHandler.LogRetryMetrics(msg)

			var msgData models.UpdateMessageMessage
			if err := json.Unmarshal(msg.Body, &msgData); err != nil {
				log.Printf("Error unmarshaling message: %v", err)
				// Parsing errors shouldn't be retried - send to DLQ
				msg.Nack(false, false)
				continue
			}

			if err := c.messageHandler.UpdateMessage(msgData); err != nil {
				log.Printf("Error updating message: %v", err)
				// Use retry handler with exponential backoff
				if retryErr := c.retryHandler.HandleFailedMessage(ch, msg, queueName, err); retryErr != nil {
					log.Printf("Error handling retry: %v", retryErr)
					msg.Nack(false, false)
				}
			} else {
				msg.Ack(false)
				retryCount := c.retryHandler.GetRetryCount(msg)
				if retryCount > 0 {
					log.Printf("Successfully updated message %d in chat %d after %d retries", 
						msgData.MessageNumber, msgData.ChatNumber, retryCount)
				} else {
					log.Printf("Updated message %d in chat %d", msgData.MessageNumber, msgData.ChatNumber)
				}
			}
		}
	}
}
