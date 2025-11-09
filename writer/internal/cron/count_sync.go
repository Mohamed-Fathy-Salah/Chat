package cron

import (
	"context"
	"fmt"
	"log"
	"strconv"
	"strings"
	"time"

	"github.com/chat/writer/internal/database"
	"github.com/redis/go-redis/v9"
)

type CountSync struct {
	db          *database.DB
	redisClient *database.RedisClient
}

type CountUpdate struct {
	Token string
	Count int
}

type messageUpdate struct {
	token      string
	chatNumber int
	count      int
}

func NewCountSync(db *database.DB, redisClient *database.RedisClient) *CountSync {
	return &CountSync{
		db:          db,
		redisClient: redisClient,
	}
}

func (cs *CountSync) Start(ctx context.Context) {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	log.Println("Starting count sync cron job (every 10 seconds)...")

	// Run immediately on start
	cs.syncCounts()

	for {
		select {
		case <-ctx.Done():
			log.Println("CountSync: Shutting down gracefully...")
			// Perform final sync before stopping
			log.Println("CountSync: Performing final sync...")
			cs.syncCounts()
			log.Println("CountSync: Final sync completed")
			return
		case <-ticker.C:
			cs.syncCounts()
		}
	}
}

func (cs *CountSync) syncCounts() {
	if err := cs.syncChatsCount(); err != nil {
		log.Printf("Error syncing chats count: %v", err)
	}

	if err := cs.syncMessagesCount(); err != nil {
		log.Printf("Error syncing messages count: %v", err)
	}
}

func (cs *CountSync) syncChatsCount() error {
	// Get all changed tokens from Redis set
	tokens, err := cs.redisClient.SMembers("chat_changes")
	if err != nil {
		return fmt.Errorf("failed to get chat_changes set: %w", err)
	}

	if len(tokens) == 0 {
		return nil
	}

	// Clear the set immediately to avoid reprocessing
	if err := cs.redisClient.Del("chat_changes"); err != nil {
		log.Printf("Warning: Failed to clear chat_changes set: %v", err)
	}

	batchSize := 100
	totalSynced := 0

	// Process tokens in batches
	for i := 0; i < len(tokens); i += batchSize {
		end := min(i + batchSize, len(tokens))
		batchTokens := tokens[i:end]

		var updates []CountUpdate
		for _, token := range batchTokens {
			// Get count from Redis counter
			redisKey := fmt.Sprintf("chat_counter:%s", token)
			count, err := cs.redisClient.GetInt(redisKey)
			if err != nil {
				if err != redis.Nil {
					log.Printf("Error getting Redis key %s: %v", redisKey, err)
				}
				continue
			}

			updates = append(updates, CountUpdate{
				Token: token,
				Count: count,
			})
		}

		// Update database for this batch
		if len(updates) > 0 {
			if err := cs.batchUpdateChatsCount(updates); err != nil {
				log.Printf("Error in batch update chats count: %v", err)
				return err
			}
			totalSynced += len(updates)
		}
	}

	if totalSynced > 0 {
		log.Printf("Synced %d chat counts", totalSynced)
	}

	return nil
}

func (cs *CountSync) syncMessagesCount() error {
	// Get all changed token:chatNumber from Redis set
	chatKeys, err := cs.redisClient.SMembers("message_changes")
	if err != nil {
		return fmt.Errorf("failed to get message_changes set: %w", err)
	}

	if len(chatKeys) == 0 {
		return nil
	}

	// Clear the set immediately to avoid reprocessing
	if err := cs.redisClient.Del("message_changes"); err != nil {
		log.Printf("Warning: Failed to clear message_changes set: %v", err)
	}

	batchSize := 100
	totalSynced := 0

	// Process chat keys in batches
	for i := 0; i < len(chatKeys); i += batchSize {
		end := min(i + batchSize, len(chatKeys))
		batchChatKeys := chatKeys[i:end]

		var updates []messageUpdate
		for _, key := range batchChatKeys {
			parts := strings.SplitN(key, ":", 2)
			if len(parts) != 2 {
				log.Printf("Invalid chat key format: %s", key)
				continue
			}
			token := parts[0]
			chatNumber, err := strconv.Atoi(parts[1])
			if err != nil {
				log.Printf("Invalid chat number in key %s: %v", key, err)
				continue
			}

			// Get count from Redis counter
			redisKey := fmt.Sprintf("message_counter:%s:%d", token, chatNumber)
			count, err := cs.redisClient.GetInt(redisKey)
			if err != nil {
				if err != redis.Nil {
					log.Printf("Error getting Redis key %s: %v", redisKey, err)
				}
				continue
			}

			updates = append(updates, messageUpdate{
				token:      token,
				chatNumber: chatNumber,
				count:      count,
			})
		}

		// Update database for this batch
		if len(updates) > 0 {
			if err := cs.batchUpdateMessagesCount(updates); err != nil {
				log.Printf("Error in batch update messages count: %v", err)
				return err
			}
			totalSynced += len(updates)
		}
	}

	if totalSynced > 0 {
		log.Printf("Synced %d message counts", totalSynced)
	}

	return nil
}

func (cs *CountSync) batchUpdateChatsCount(updates []CountUpdate) error {
	if len(updates) == 0 {
		return nil
	}

	// Use parameterized query to prevent SQL injection
	// Build placeholders for CASE statement
	var whenClauses []string
	var args []interface{}
	var tokenPlaceholders []string

	placeholderIdx := 1
	for _, update := range updates {
		// WHEN ? THEN ?
		whenClauses = append(whenClauses, fmt.Sprintf("WHEN ? THEN ?"))
		args = append(args, update.Token, update.Count)
		
		// For IN clause
		tokenPlaceholders = append(tokenPlaceholders, "?")
		placeholderIdx += 2
	}

	// Add tokens for IN clause
	for _, update := range updates {
		args = append(args, update.Token)
	}

	query := fmt.Sprintf(`
		UPDATE applications
		SET chats_count = CASE token
			%s
		END
		WHERE token IN (%s)
	`, strings.Join(whenClauses, " "), strings.Join(tokenPlaceholders, ", "))

	_, err := cs.db.Exec(query, args...)
	return err
}

func (cs *CountSync) batchUpdateMessagesCount(updates []messageUpdate) error {
	if len(updates) == 0 {
		return nil
	}

	// Use parameterized query to prevent SQL injection
	// Build placeholders for CASE statement and WHERE conditions
	var whenClauses []string
	var conditions []string
	var args []interface{}

	for _, update := range updates {
		// WHEN token = ? AND number = ? THEN ?
		whenClauses = append(whenClauses, "WHEN token = ? AND number = ? THEN ?")
		args = append(args, update.token, update.chatNumber, update.count)
		
		// (token = ? AND number = ?)
		conditions = append(conditions, "(token = ? AND number = ?)")
	}

	// Add parameters for WHERE clause
	for _, update := range updates {
		args = append(args, update.token, update.chatNumber)
	}

	query := fmt.Sprintf(`
		UPDATE chats
		SET messages_count = CASE
			%s
		END
		WHERE %s
	`, strings.Join(whenClauses, " "), strings.Join(conditions, " OR "))

	_, err := cs.db.Exec(query, args...)
	return err
}
