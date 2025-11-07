package queue

import (
	"encoding/json"
	"log"

	"github.com/chat/writer/internal/handlers"
	"github.com/chat/writer/internal/models"
)

type ChatConsumer struct {
	rabbit      *RabbitMQ
	chatHandler *handlers.ChatHandler
}

func NewChatConsumer(rabbit *RabbitMQ, chatHandler *handlers.ChatHandler) *ChatConsumer {
	return &ChatConsumer{
		rabbit:      rabbit,
		chatHandler: chatHandler,
	}
}

func (c *ChatConsumer) Start() {
	ch, err := c.rabbit.CreateChannel()
	if err != nil {
		log.Fatalf("Failed to open channel: %v", err)
	}
	defer ch.Close()

	q, err := c.rabbit.DeclareQueue(ch, "create_chats")
	if err != nil {
		log.Fatalf("Failed to declare queue: %v", err)
	}

	msgs, err := c.rabbit.Consume(ch, q.Name)
	if err != nil {
		log.Fatalf("Failed to register consumer: %v", err)
	}

	log.Println("Waiting for create_chats messages...")

	for msg := range msgs {
		var chatMsg models.CreateChatMessage
		if err := json.Unmarshal(msg.Body, &chatMsg); err != nil {
			log.Printf("Error unmarshaling message: %v", err)
			msg.Nack(false, false)
			continue
		}

		if err := c.chatHandler.CreateChat(chatMsg); err != nil {
			log.Printf("Error creating chat: %v", err)
			msg.Nack(false, true) // Requeue
		} else {
			msg.Ack(false)
			log.Printf("Created chat %d for application %s", chatMsg.ChatNumber, chatMsg.Token)
		}
	}
}
