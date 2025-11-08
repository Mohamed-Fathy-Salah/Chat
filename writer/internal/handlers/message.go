package handlers

import (
	"fmt"
	"log"
	"time"

	"github.com/chat/writer/internal/database"
	"github.com/chat/writer/internal/models"
	"github.com/chat/writer/internal/services"
)

type MessageHandler struct {
	db          *database.DB
	esService   *services.ElasticsearchService
	redisClient *database.RedisClient
}

func NewMessageHandler(db *database.DB, esService *services.ElasticsearchService, redisClient *database.RedisClient) *MessageHandler {
	return &MessageHandler{
		db:          db,
		esService:   esService,
		redisClient: redisClient,
	}
}

func (h *MessageHandler) CreateMessage(msg models.CreateMessageMessage) error {
	// Parse date
	createdAt, err := time.Parse(time.RFC3339, msg.Date)
	if err != nil {
		createdAt = time.Now()
	}

	// Insert message directly using token and chat_number (no need to lookup chat_id)
	result, err := h.db.Exec(`
		INSERT INTO messages (token, chat_number, number, body, creator_id, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	`, msg.Token, msg.ChatNumber, msg.MessageNumber, msg.Body, msg.SenderID, createdAt, createdAt)

	if err != nil {
		return err
	}

	// Get the inserted message ID
	messageID, err := result.LastInsertId()
	if err != nil {
		log.Printf("Warning: Failed to get message ID: %v", err)
	}

	// Index in Elasticsearch if available
	if h.esService != nil {
		// Get sender name for Elasticsearch
		var senderName string
		err := h.db.QueryRow("SELECT name FROM users WHERE id = ?", msg.SenderID).Scan(&senderName)
		if err != nil {
			log.Printf("Warning: Failed to get sender name: %v", err)
			senderName = ""
		}

		doc := services.MessageDocument{
			ID:         int(messageID),
			Token:      msg.Token,
			ChatNumber: msg.ChatNumber,
			Number:     msg.MessageNumber,
			Body:       msg.Body,
			SenderID:   msg.SenderID,
			SenderName: senderName,
			CreatedAt:  createdAt.Format(time.RFC3339),
		}

		if err := h.esService.IndexMessage(doc); err != nil {
			log.Printf("Warning: Failed to index message in Elasticsearch: %v", err)
		} else {
			log.Printf("Indexed message %d in Elasticsearch", msg.MessageNumber)
		}
	}

	// Add token:chatNumber to Redis set for tracking changes
	if h.redisClient != nil {
		key := fmt.Sprintf("%s:%d", msg.Token, msg.ChatNumber)
		if err := h.redisClient.SAdd("message_changes", key); err != nil {
			// Log but don't fail the operation
			log.Printf("Warning: Failed to add to message_changes set: %v", err)
		}
	}

	return nil
}

func (h *MessageHandler) UpdateMessage(msg models.UpdateMessageMessage) error {
	// Update message directly using token, chat_number, and number
	result, err := h.db.Exec(`
		UPDATE messages
		SET body = ?, updated_at = NOW()
		WHERE token = ? AND chat_number = ? AND number = ?
	`, msg.Body, msg.Token, msg.ChatNumber, msg.MessageNumber)

	if err != nil {
		return err
	}

	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("message not found")
	}

	// Update in Elasticsearch if available
	if h.esService != nil {
		if err := h.esService.UpdateMessage(msg.Token, msg.ChatNumber, msg.MessageNumber, msg.Body); err != nil {
			log.Printf("Warning: Failed to update message in Elasticsearch: %v", err)
		} else {
			log.Printf("Updated message %d in Elasticsearch", msg.MessageNumber)
		}
	}

	return nil
}
