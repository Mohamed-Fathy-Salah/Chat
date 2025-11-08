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
	db        *database.DB
	esService *services.ElasticsearchService
}

func NewMessageHandler(db *database.DB, esService *services.ElasticsearchService) *MessageHandler {
	return &MessageHandler{
		db:        db,
		esService: esService,
	}
}

func (h *MessageHandler) CreateMessage(msg models.CreateMessageMessage) error {
	// Get chat ID
	var chatID int
	err := h.db.QueryRow(`
		SELECT c.id 
		FROM chats c 
		JOIN applications a ON c.application_id = a.id 
		WHERE a.token = ? AND c.number = ?
	`, msg.Token, msg.ChatNumber).Scan(&chatID)
	if err != nil {
		return fmt.Errorf("failed to find chat: %w", err)
	}

	// Parse date
	createdAt, err := time.Parse(time.RFC3339, msg.Date)
	if err != nil {
		createdAt = time.Now()
	}

	// Insert message (no count update)
	result, err := h.db.Exec(`
		INSERT INTO messages (chat_id, token, chat_number, number, body, creator_id, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	`, chatID, msg.Token, msg.ChatNumber, msg.MessageNumber, msg.Body, msg.SenderID, createdAt, createdAt)

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
		doc := services.MessageDocument{
			ID:         int(messageID),
			ChatID:     chatID,
			Token:      msg.Token,
			ChatNumber: msg.ChatNumber,
			Number:     msg.MessageNumber,
			Body:       msg.Body,
			SenderID:   msg.SenderID,
			CreatedAt:  createdAt.Format(time.RFC3339),
		}

		if err := h.esService.IndexMessage(doc); err != nil {
			log.Printf("Warning: Failed to index message in Elasticsearch: %v", err)
		} else {
			log.Printf("Indexed message %d in Elasticsearch", msg.MessageNumber)
		}
	}

	return nil
}

func (h *MessageHandler) UpdateMessage(msg models.UpdateMessageMessage) error {
	// Update message
	result, err := h.db.Exec(`
		UPDATE messages m
		JOIN chats c ON m.chat_id = c.id
		JOIN applications a ON c.application_id = a.id
		SET m.body = ?, m.updated_at = NOW()
		WHERE a.token = ? AND c.number = ? AND m.number = ?
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
