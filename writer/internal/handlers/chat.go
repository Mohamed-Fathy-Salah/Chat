package handlers

import (
	"fmt"

	"github.com/chat/writer/internal/database"
	"github.com/chat/writer/internal/models"
)

type ChatHandler struct {
	db *database.DB
}

func NewChatHandler(db *database.DB) *ChatHandler {
	return &ChatHandler{db: db}
}

func (h *ChatHandler) CreateChat(msg models.CreateChatMessage) error {
	// Get application ID
	var appID int
	err := h.db.QueryRow("SELECT id FROM applications WHERE token = ?", msg.Token).Scan(&appID)
	if err != nil {
		return fmt.Errorf("failed to find application: %w", err)
	}

	// Insert chat (no count update)
	_, err = h.db.Exec(`
		INSERT INTO chats (application_id, token, number, creator_id, created_at, updated_at)
		VALUES (?, ?, ?, ?, NOW(), NOW())
	`, appID, msg.Token, msg.ChatNumber, msg.CreatorID)

	return err
}
