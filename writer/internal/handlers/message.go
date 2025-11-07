package handlers

import (
	"fmt"
	"time"

	"github.com/chat/writer/internal/database"
	"github.com/chat/writer/internal/models"
)

type MessageHandler struct {
	db *database.DB
}

func NewMessageHandler(db *database.DB) *MessageHandler {
	return &MessageHandler{db: db}
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
	_, err = h.db.Exec(`
		INSERT INTO messages (chat_id, token, chat_number, number, body, creator_id, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	`, chatID, msg.Token, msg.ChatNumber, msg.MessageNumber, msg.Body, msg.SenderID, createdAt, createdAt)

	return err
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

	return nil
}
