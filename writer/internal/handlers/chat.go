package handlers

import (
	"fmt"

	"github.com/chat/writer/internal/database"
	"github.com/chat/writer/internal/models"
)

type ChatHandler struct {
	db          *database.DB
	redisClient *database.RedisClient
}

func NewChatHandler(db *database.DB, redisClient *database.RedisClient) *ChatHandler {
	return &ChatHandler{
		db:          db,
		redisClient: redisClient,
	}
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

	if err != nil {
		return err
	}

	// Add token to Redis set for tracking changes
	if h.redisClient != nil {
		if err := h.redisClient.SAdd("chat_changes", msg.Token); err != nil {
			// Log but don't fail the operation
			fmt.Printf("Warning: Failed to add to chat_changes set: %v\n", err)
		}
	}

	return nil
}
