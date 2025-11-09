package queue

import (
	"context"
	"encoding/json"
	"log"

	"github.com/chat/writer/internal/handlers"
	"github.com/chat/writer/internal/models"
)

type ChatConsumer struct {
	rabbit       *RabbitMQ
	chatHandler  *handlers.ChatHandler
	retryHandler *RetryHandler
}

func NewChatConsumer(rabbit *RabbitMQ, chatHandler *handlers.ChatHandler) *ChatConsumer {
	return &ChatConsumer{
		rabbit:       rabbit,
		chatHandler:  chatHandler,
		retryHandler: NewRetryHandler(),
	}
}

func (c *ChatConsumer) Start(ctx context.Context) {
	ch, err := c.rabbit.CreateChannel()
	if err != nil {
		log.Fatalf("Failed to open channel: %v", err)
	}
	defer ch.Close()

	queueName := "create_chats"
	q, err := c.rabbit.DeclareQueueWithDLQ(ch, queueName)
	if err != nil {
		log.Fatalf("Failed to declare queue with DLQ: %v", err)
	}

	msgs, err := c.rabbit.Consume(ch, q.Name)
	if err != nil {
		log.Fatalf("Failed to register consumer: %v", err)
	}

	log.Println("Waiting for create_chats messages...")

	for {
		select {
		case <-ctx.Done():
			log.Println("ChatConsumer: Shutting down gracefully...")
			return
		case msg, ok := <-msgs:
			if !ok {
				log.Println("ChatConsumer: Channel closed")
				return
			}

			// Log retry metrics if this is a retry
			c.retryHandler.LogRetryMetrics(msg)

			var chatMsg models.CreateChatMessage
			if err := json.Unmarshal(msg.Body, &chatMsg); err != nil {
				log.Printf("Error unmarshaling message: %v", err)
				// Parsing errors shouldn't be retried - send to DLQ
				msg.Nack(false, false)
				continue
			}

			if err := c.chatHandler.CreateChat(chatMsg); err != nil {
				log.Printf("Error creating chat: %v", err)
				// Use retry handler with exponential backoff
				if retryErr := c.retryHandler.HandleFailedMessage(ch, msg, queueName, err); retryErr != nil {
					log.Printf("Error handling retry: %v", retryErr)
					msg.Nack(false, false)
				}
			} else {
				msg.Ack(false)
				retryCount := c.retryHandler.GetRetryCount(msg)
				if retryCount > 0 {
					log.Printf("Successfully created chat %d for application %s after %d retries", 
						chatMsg.ChatNumber, chatMsg.Token, retryCount)
				} else {
					log.Printf("Created chat %d for application %s", chatMsg.ChatNumber, chatMsg.Token)
				}
			}
		}
	}
}
