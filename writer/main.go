package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/chat/writer/internal/config"
	"github.com/chat/writer/internal/cron"
	"github.com/chat/writer/internal/database"
	"github.com/chat/writer/internal/handlers"
	"github.com/chat/writer/internal/queue"
)

func main() {
	log.Println("Starting Writer Service...")

	// Load configuration
	cfg := config.Load()
	ctx := context.Background()

	// Connect to MySQL
	db, err := database.Connect(cfg.DatabaseHost, cfg.DatabaseUser, cfg.DatabasePassword, cfg.DatabaseName)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()

	// Connect to Redis
	redisClient, err := database.ConnectRedis(cfg.RedisURL, ctx)
	if err != nil {
		log.Fatalf("Failed to connect to Redis: %v", err)
	}
	defer redisClient.Close()

	// Connect to RabbitMQ
	rabbit, err := queue.Connect(cfg.RabbitMQURL)
	if err != nil {
		log.Fatalf("Failed to connect to RabbitMQ: %v", err)
	}
	defer rabbit.Close()

	// Initialize handlers
	chatHandler := handlers.NewChatHandler(db)
	messageHandler := handlers.NewMessageHandler(db)

	// Initialize consumers
	chatConsumer := queue.NewChatConsumer(rabbit, chatHandler)
	messageConsumer := queue.NewMessageConsumer(rabbit, messageHandler)

	// Initialize cron job
	countSync := cron.NewCountSync(db, redisClient)

	// Start consumers in separate goroutines
	go chatConsumer.Start()
	go messageConsumer.StartCreateConsumer()
	go messageConsumer.StartUpdateConsumer()

	// Start cron job
	go countSync.Start()

	log.Println("Writer Service started successfully")

	// Wait for interrupt signal
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan

	log.Println("Shutting down Writer Service...")
}
