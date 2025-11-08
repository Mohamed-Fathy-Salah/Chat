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
	// Insert chat directly using token (no need to lookup application_id)
	_, err := h.db.Exec(`
		INSERT INTO chats (token, number, creator_id, created_at, updated_at)
		VALUES (?, ?, ?, NOW(), NOW())
	`, msg.Token, msg.ChatNumber, msg.CreatorID)

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
