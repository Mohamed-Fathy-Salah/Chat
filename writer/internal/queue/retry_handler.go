package queue

import (
	"fmt"
	"log"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
)

const (
	MaxRetries           = 5
	InitialRetryDelay    = 1 * time.Second
	MaxRetryDelay        = 5 * time.Minute
	RetryCountHeader     = "x-retry-count"
	OriginalQueueHeader  = "x-original-queue"
	FirstFailureHeader   = "x-first-failure-time"
)

type RetryHandler struct {
	maxRetries int
}

func NewRetryHandler() *RetryHandler {
	return &RetryHandler{
		maxRetries: MaxRetries,
	}
}

// GetRetryCount extracts the retry count from message headers
func (rh *RetryHandler) GetRetryCount(msg amqp.Delivery) int {
	if msg.Headers == nil {
		return 0
	}
	
	if count, ok := msg.Headers[RetryCountHeader].(int32); ok {
		return int(count)
	}
	
	return 0
}

// CalculateBackoff calculates exponential backoff delay
func (rh *RetryHandler) CalculateBackoff(retryCount int) time.Duration {
	// Exponential backoff: 1s, 2s, 4s, 8s, 16s, ... up to MaxRetryDelay
	delay := InitialRetryDelay * time.Duration(1<<uint(retryCount))
	
	if delay > MaxRetryDelay {
		delay = MaxRetryDelay
	}
	
	return delay
}

// ShouldRetry determines if a message should be retried
func (rh *RetryHandler) ShouldRetry(msg amqp.Delivery) bool {
	retryCount := rh.GetRetryCount(msg)
	return retryCount < rh.maxRetries
}

// PrepareRetry prepares a message for retry with updated headers
func (rh *RetryHandler) PrepareRetry(msg amqp.Delivery, originalQueue string) amqp.Publishing {
	retryCount := rh.GetRetryCount(msg) + 1
	
	headers := make(amqp.Table)
	if msg.Headers != nil {
		for k, v := range msg.Headers {
			headers[k] = v
		}
	}
	
	headers[RetryCountHeader] = int32(retryCount)
	headers[OriginalQueueHeader] = originalQueue
	
	// Set first failure time if not already set
	if _, ok := headers[FirstFailureHeader]; !ok {
		headers[FirstFailureHeader] = time.Now().Unix()
	}
	
	return amqp.Publishing{
		DeliveryMode: amqp.Persistent,
		ContentType:  msg.ContentType,
		Body:         msg.Body,
		Headers:      headers,
	}
}

// HandleFailedMessage handles a failed message with retry logic
func (rh *RetryHandler) HandleFailedMessage(ch *amqp.Channel, msg amqp.Delivery, queueName string, err error) error {
	retryCount := rh.GetRetryCount(msg)
	
	log.Printf("Message processing failed (retry %d/%d): %v", retryCount, rh.maxRetries, err)
	
	if rh.ShouldRetry(msg) {
		// Calculate backoff delay
		delay := rh.CalculateBackoff(retryCount)
		log.Printf("Retrying message after %v (attempt %d/%d)", delay, retryCount+1, rh.maxRetries)
		
		// Nack with requeue to retry queue with delay
		return rh.requeueWithDelay(ch, msg, queueName, delay)
	}
	
	// Max retries exceeded, send to DLQ
	log.Printf("Max retries exceeded, sending to DLQ")
	firstFailure := rh.getFirstFailureTime(msg)
	log.Printf("Message first failed at %v, total time in retry: %v", 
		time.Unix(firstFailure, 0), 
		time.Since(time.Unix(firstFailure, 0)))
	
	// Nack without requeue - will go to DLQ via dead letter exchange
	return msg.Nack(false, false)
}

// requeueWithDelay requeues a message with a delay using TTL
func (rh *RetryHandler) requeueWithDelay(ch *amqp.Channel, msg amqp.Delivery, originalQueue string, delay time.Duration) error {
	// Create delay queue with TTL
	delayQueueName := fmt.Sprintf("%s.retry.%dms", originalQueue, delay.Milliseconds())
	
	_, err := ch.QueueDeclare(
		delayQueueName,
		true,  // durable
		false, // delete when unused
		false, // exclusive
		false, // no-wait
		amqp.Table{
			"x-message-ttl":            int32(delay.Milliseconds()),
			"x-dead-letter-exchange":   "", // default exchange
			"x-dead-letter-routing-key": originalQueue,
		},
	)
	if err != nil {
		return err
	}
	
	// Prepare message with updated retry count
	publishing := rh.PrepareRetry(msg, originalQueue)
	
	// Publish to delay queue
	err = ch.Publish(
		"",             // exchange
		delayQueueName, // routing key
		false,          // mandatory
		false,          // immediate
		publishing,
	)
	if err != nil {
		return err
	}
	
	// Ack original message
	return msg.Ack(false)
}

// getFirstFailureTime extracts the first failure timestamp from headers
func (rh *RetryHandler) getFirstFailureTime(msg amqp.Delivery) int64 {
	if msg.Headers == nil {
		return time.Now().Unix()
	}
	
	if timestamp, ok := msg.Headers[FirstFailureHeader].(int64); ok {
		return timestamp
	}
	
	return time.Now().Unix()
}

// LogRetryMetrics logs retry metrics for monitoring
func (rh *RetryHandler) LogRetryMetrics(msg amqp.Delivery) {
	retryCount := rh.GetRetryCount(msg)
	if retryCount > 0 {
		firstFailure := rh.getFirstFailureTime(msg)
		timeSinceFirstFailure := time.Since(time.Unix(firstFailure, 0))
		
		log.Printf("Retry metrics - Count: %d, Time since first failure: %v", 
			retryCount, timeSinceFirstFailure)
	}
}
