package cron

import (
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

type ChatCountUpdate struct {
	Token string
	Count int
}

type MessageCountUpdate struct {
	Token      string
	ChatNumber int
	Count      int
}

func NewCountSync(db *database.DB, redisClient *database.RedisClient) *CountSync {
	return &CountSync{
		db:          db,
		redisClient: redisClient,
	}
}

func (cs *CountSync) Start() {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	log.Println("Starting count sync cron job (every 10 seconds)...")

	// Run immediately on start
	cs.syncCounts()

	for range ticker.C {
		cs.syncCounts()
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
	// Get all application tokens
	rows, err := cs.db.Query("SELECT token FROM applications")
	if err != nil {
		return err
	}
	defer rows.Close()

	var tokens []string
	for rows.Next() {
		var token string
		if err := rows.Scan(&token); err != nil {
			continue
		}
		tokens = append(tokens, token)
	}

	// Collect all updates to batch
	updates := []ChatCountUpdate{}

	for _, token := range tokens {
		redisKey := fmt.Sprintf("chat_counter:%s", token)
		value, err := cs.redisClient.GetString(redisKey)
		if err != nil {
			if err != redis.Nil {
				log.Printf("Error getting Redis key %s: %v", redisKey, err)
			}
			continue
		}

		// Check if value has been modified (first character is '1')
		if len(value) > 0 && value[0] == '1' {
			// Extract count (everything after first character)
			count, err := strconv.Atoi(value[1:])
			if err != nil {
				log.Printf("Error parsing count from %s: %v", value, err)
				continue
			}

			updates = append(updates, ChatCountUpdate{
				Token: token,
				Count: count,
			})

			// Reset modified flag (set first character to '0')
			newValue := "0" + value[1:]
			if err := cs.redisClient.SetString(redisKey, newValue); err != nil {
				log.Printf("Error resetting flag for %s: %v", redisKey, err)
			}
		}
	}

	// Batch update database
	if len(updates) > 0 {
		if err := cs.batchUpdateChatsCount(updates); err != nil {
			log.Printf("Error in batch update chats count: %v", err)
			return err
		}
		log.Printf("Synced %d chat counts", len(updates))
	}

	return nil
}

func (cs *CountSync) syncMessagesCount() error {
	// Get all chats
	rows, err := cs.db.Query(`
		SELECT a.token, c.number 
		FROM chats c 
		JOIN applications a ON c.application_id = a.id
	`)
	if err != nil {
		return err
	}
	defer rows.Close()

	type chatKey struct {
		token      string
		chatNumber int
	}

	var chatKeys []chatKey
	for rows.Next() {
		var token string
		var chatNumber int
		if err := rows.Scan(&token, &chatNumber); err != nil {
			continue
		}
		chatKeys = append(chatKeys, chatKey{token, chatNumber})
	}

	// Collect all updates to batch
	updates := []MessageCountUpdate{}

	for _, ck := range chatKeys {
		redisKey := fmt.Sprintf("message_counter:%s:%d", ck.token, ck.chatNumber)
		value, err := cs.redisClient.GetString(redisKey)
		if err != nil {
			if err != redis.Nil {
				log.Printf("Error getting Redis key %s: %v", redisKey, err)
			}
			continue
		}

		// Check if value has been modified (first character is '1')
		if len(value) > 0 && value[0] == '1' {
			// Extract count (everything after first character)
			count, err := strconv.Atoi(value[1:])
			if err != nil {
				log.Printf("Error parsing count from %s: %v", value, err)
				continue
			}

			updates = append(updates, MessageCountUpdate{
				Token:      ck.token,
				ChatNumber: ck.chatNumber,
				Count:      count,
			})

			// Reset modified flag (set first character to '0')
			newValue := "0" + value[1:]
			if err := cs.redisClient.SetString(redisKey, newValue); err != nil {
				log.Printf("Error resetting flag for %s: %v", redisKey, err)
			}
		}
	}

	// Batch update database
	if len(updates) > 0 {
		if err := cs.batchUpdateMessagesCount(updates); err != nil {
			log.Printf("Error in batch update messages count: %v", err)
			return err
		}
		log.Printf("Synced %d message counts", len(updates))
	}

	return nil
}

func (cs *CountSync) batchUpdateChatsCount(updates []ChatCountUpdate) error {
	if len(updates) == 0 {
		return nil
	}

	// Build batch update query using CASE statement
	var tokens []string
	var whenClauses []string
	
	for _, update := range updates {
		tokens = append(tokens, fmt.Sprintf("'%s'", update.Token))
		whenClauses = append(whenClauses, fmt.Sprintf("WHEN '%s' THEN %d", update.Token, update.Count))
	}

	query := fmt.Sprintf(`
		UPDATE applications
		SET chats_count = CASE token
			%s
		END
		WHERE token IN (%s)
	`, strings.Join(whenClauses, " "), strings.Join(tokens, ", "))

	_, err := cs.db.Exec(query)
	return err
}

func (cs *CountSync) batchUpdateMessagesCount(updates []MessageCountUpdate) error {
	if len(updates) == 0 {
		return nil
	}

	// Build batch update query using CASE statement
	var conditions []string
	var whenClauses []string
	
	for _, update := range updates {
		condition := fmt.Sprintf("(a.token = '%s' AND c.number = %d)", update.Token, update.ChatNumber)
		conditions = append(conditions, condition)
		whenClauses = append(whenClauses, 
			fmt.Sprintf("WHEN a.token = '%s' AND c.number = %d THEN %d", 
				update.Token, update.ChatNumber, update.Count))
	}

	query := fmt.Sprintf(`
		UPDATE chats c
		JOIN applications a ON c.application_id = a.id
		SET c.messages_count = CASE
			%s
		END
		WHERE %s
	`, strings.Join(whenClauses, " "), strings.Join(conditions, " OR "))

	_, err := cs.db.Exec(query)
	return err
}
