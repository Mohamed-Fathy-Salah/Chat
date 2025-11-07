package queue

import (
	"encoding/json"
	"log"

	"github.com/chat/writer/internal/handlers"
	"github.com/chat/writer/internal/models"
)

type MessageConsumer struct {
	rabbit         *RabbitMQ
	messageHandler *handlers.MessageHandler
}

func NewMessageConsumer(rabbit *RabbitMQ, messageHandler *handlers.MessageHandler) *MessageConsumer {
	return &MessageConsumer{
		rabbit:         rabbit,
		messageHandler: messageHandler,
	}
}

func (c *MessageConsumer) StartCreateConsumer() {
	ch, err := c.rabbit.CreateChannel()
	if err != nil {
		log.Fatalf("Failed to open channel: %v", err)
	}
	defer ch.Close()

	q, err := c.rabbit.DeclareQueue(ch, "create_messages")
	if err != nil {
		log.Fatalf("Failed to declare queue: %v", err)
	}

	msgs, err := c.rabbit.Consume(ch, q.Name)
	if err != nil {
		log.Fatalf("Failed to register consumer: %v", err)
	}

	log.Println("Waiting for create_messages messages...")

	for msg := range msgs {
		var msgData models.CreateMessageMessage
		if err := json.Unmarshal(msg.Body, &msgData); err != nil {
			log.Printf("Error unmarshaling message: %v", err)
			msg.Nack(false, false)
			continue
		}

		if err := c.messageHandler.CreateMessage(msgData); err != nil {
			log.Printf("Error creating message: %v", err)
			msg.Nack(false, true) // Requeue
		} else {
			msg.Ack(false)
			log.Printf("Created message %d in chat %d", msgData.MessageNumber, msgData.ChatNumber)
		}
	}
}

func (c *MessageConsumer) StartUpdateConsumer() {
	ch, err := c.rabbit.CreateChannel()
	if err != nil {
		log.Fatalf("Failed to open channel: %v", err)
	}
	defer ch.Close()

	q, err := c.rabbit.DeclareQueue(ch, "update_messages")
	if err != nil {
		log.Fatalf("Failed to declare queue: %v", err)
	}

	msgs, err := c.rabbit.Consume(ch, q.Name)
	if err != nil {
		log.Fatalf("Failed to register consumer: %v", err)
	}

	log.Println("Waiting for update_messages messages...")

	for msg := range msgs {
		var msgData models.UpdateMessageMessage
		if err := json.Unmarshal(msg.Body, &msgData); err != nil {
			log.Printf("Error unmarshaling message: %v", err)
			msg.Nack(false, false)
			continue
		}

		if err := c.messageHandler.UpdateMessage(msgData); err != nil {
			log.Printf("Error updating message: %v", err)
			msg.Nack(false, true) // Requeue
		} else {
			msg.Ack(false)
			log.Printf("Updated message %d in chat %d", msgData.MessageNumber, msgData.ChatNumber)
		}
	}
}
