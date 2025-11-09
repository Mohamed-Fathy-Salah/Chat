package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/chat/writer/internal/config"
	"github.com/chat/writer/internal/cron"
	"github.com/chat/writer/internal/database"
	"github.com/chat/writer/internal/handlers"
	"github.com/chat/writer/internal/queue"
	"github.com/chat/writer/internal/services"
)

func main() {
	log.Println("Starting Writer Service...")

	// Load configuration
	cfg := config.Load()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

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

	// Connect to Elasticsearch
	esClient, err := database.ConnectElasticsearch(cfg.ElasticsearchURL)
	if err != nil {
		log.Printf("Warning: Failed to connect to Elasticsearch: %v", err)
		log.Println("Continuing without Elasticsearch support")
	}

	// Initialize Elasticsearch service
	var esService *services.ElasticsearchService
	if esClient != nil {
		esService = services.NewElasticsearchService(esClient, ctx)
	}

	// Initialize handlers
	chatHandler := handlers.NewChatHandler(db, redisClient)
	messageHandler := handlers.NewMessageHandler(db, esService, redisClient)

	// Initialize consumers
	chatConsumer := queue.NewChatConsumer(rabbit, chatHandler)
	messageConsumer := queue.NewMessageConsumer(rabbit, messageHandler)

	// Initialize cron job
	countSync := cron.NewCountSync(db, redisClient)

	// WaitGroup to track all goroutines
	var wg sync.WaitGroup

	// Start consumers in separate goroutines
	wg.Add(1)
	go func() {
		defer wg.Done()
		chatConsumer.Start(ctx)
	}()

	wg.Add(1)
	go func() {
		defer wg.Done()
		messageConsumer.StartCreateConsumer(ctx)
	}()

	wg.Add(1)
	go func() {
		defer wg.Done()
		messageConsumer.StartUpdateConsumer(ctx)
	}()

	// Start cron job
	wg.Add(1)
	go func() {
		defer wg.Done()
		countSync.Start(ctx)
	}()

	log.Println("Writer Service started successfully")

	// Wait for interrupt signal
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan

	log.Println("Shutting down Writer Service...")

	// Cancel context to signal all goroutines to stop
	cancel()

	// Wait for all goroutines to finish with timeout
	done := make(chan struct{})
	go func() {
		wg.Wait()
		close(done)
	}()

	select {
	case <-done:
		log.Println("All goroutines stopped gracefully")
	case <-time.After(30 * time.Second):
		log.Println("Shutdown timeout exceeded, forcing exit")
	}

	log.Println("Writer Service stopped")
}
