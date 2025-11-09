package queue

import (
	"testing"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
)

func TestGetRetryCount(t *testing.T) {
	rh := NewRetryHandler()

	tests := []struct {
		name     string
		headers  amqp.Table
		expected int
	}{
		{
			name:     "No headers",
			headers:  nil,
			expected: 0,
		},
		{
			name:     "No retry header",
			headers:  amqp.Table{"other": "value"},
			expected: 0,
		},
		{
			name:     "Retry count 3",
			headers:  amqp.Table{RetryCountHeader: int32(3)},
			expected: 3,
		},
		{
			name:     "Retry count 5",
			headers:  amqp.Table{RetryCountHeader: int32(5)},
			expected: 5,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			msg := amqp.Delivery{Headers: tt.headers}
			got := rh.GetRetryCount(msg)
			if got != tt.expected {
				t.Errorf("GetRetryCount() = %d, want %d", got, tt.expected)
			}
		})
	}
}

func TestCalculateBackoff(t *testing.T) {
	rh := NewRetryHandler()

	tests := []struct {
		retryCount   int
		expectedMin  time.Duration
		expectedMax  time.Duration
		description  string
	}{
		{0, 1 * time.Second, 1 * time.Second, "First retry: 1s"},
		{1, 2 * time.Second, 2 * time.Second, "Second retry: 2s"},
		{2, 4 * time.Second, 4 * time.Second, "Third retry: 4s"},
		{3, 8 * time.Second, 8 * time.Second, "Fourth retry: 8s"},
		{4, 16 * time.Second, 16 * time.Second, "Fifth retry: 16s"},
		{5, 32 * time.Second, 32 * time.Second, "Sixth retry: 32s"},
		{10, MaxRetryDelay, MaxRetryDelay, "Large retry: capped at max"},
	}

	for _, tt := range tests {
		t.Run(tt.description, func(t *testing.T) {
			got := rh.CalculateBackoff(tt.retryCount)
			if got < tt.expectedMin || got > tt.expectedMax {
				t.Errorf("CalculateBackoff(%d) = %v, want between %v and %v",
					tt.retryCount, got, tt.expectedMin, tt.expectedMax)
			}
		})
	}
}

func TestShouldRetry(t *testing.T) {
	rh := NewRetryHandler()

	tests := []struct {
		name        string
		retryCount  int32
		shouldRetry bool
	}{
		{"No retries yet", 0, true},
		{"First retry", 1, true},
		{"Fourth retry", 4, true},
		{"Max retries reached", 5, false},
		{"Exceeded max retries", 6, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			msg := amqp.Delivery{
				Headers: amqp.Table{RetryCountHeader: tt.retryCount},
			}
			got := rh.ShouldRetry(msg)
			if got != tt.shouldRetry {
				t.Errorf("ShouldRetry() = %v, want %v", got, tt.shouldRetry)
			}
		})
	}
}

func TestPrepareRetry(t *testing.T) {
	rh := NewRetryHandler()

	msg := amqp.Delivery{
		ContentType: "application/json",
		Body:        []byte(`{"test":"data"}`),
		Headers: amqp.Table{
			RetryCountHeader: int32(2),
			"custom-header":  "value",
		},
	}

	publishing := rh.PrepareRetry(msg, "test_queue")

	// Check retry count incremented
	retryCount, ok := publishing.Headers[RetryCountHeader].(int32)
	if !ok || retryCount != 3 {
		t.Errorf("Expected retry count 3, got %v", retryCount)
	}

	// Check original queue set
	origQueue, ok := publishing.Headers[OriginalQueueHeader].(string)
	if !ok || origQueue != "test_queue" {
		t.Errorf("Expected original queue 'test_queue', got %v", origQueue)
	}

	// Check custom header preserved
	customHeader, ok := publishing.Headers["custom-header"].(string)
	if !ok || customHeader != "value" {
		t.Errorf("Expected custom header preserved, got %v", customHeader)
	}

	// Check first failure time set
	if _, ok := publishing.Headers[FirstFailureHeader]; !ok {
		t.Error("Expected first failure time to be set")
	}

	// Check body preserved
	if string(publishing.Body) != string(msg.Body) {
		t.Errorf("Body not preserved: got %s, want %s", publishing.Body, msg.Body)
	}

	// Check delivery mode
	if publishing.DeliveryMode != amqp.Persistent {
		t.Error("Expected persistent delivery mode")
	}
}

func TestPrepareRetry_PreservesFirstFailureTime(t *testing.T) {
	rh := NewRetryHandler()

	firstFailureTime := time.Now().Add(-1 * time.Hour).Unix()

	msg := amqp.Delivery{
		Body: []byte(`{"test":"data"}`),
		Headers: amqp.Table{
			RetryCountHeader:   int32(1),
			FirstFailureHeader: firstFailureTime,
		},
	}

	publishing := rh.PrepareRetry(msg, "test_queue")

	// Check first failure time preserved
	preservedTime, ok := publishing.Headers[FirstFailureHeader].(int64)
	if !ok || preservedTime != firstFailureTime {
		t.Errorf("Expected first failure time %d to be preserved, got %v", firstFailureTime, preservedTime)
	}
}

func TestExponentialBackoffProgression(t *testing.T) {
	rh := NewRetryHandler()

	var previousDelay time.Duration
	for i := 0; i < 5; i++ {
		delay := rh.CalculateBackoff(i)
		
		// Each delay should be double the previous (exponential)
		if i > 0 && delay <= previousDelay {
			t.Errorf("Backoff not exponential: retry %d has delay %v, previous was %v",
				i, delay, previousDelay)
		}
		
		previousDelay = delay
	}
}

func TestRetryCountIncrement(t *testing.T) {
	rh := NewRetryHandler()

	// Start with no retries
	msg := amqp.Delivery{
		Body:    []byte(`{"test":"data"}`),
		Headers: amqp.Table{},
	}

	// Simulate multiple retries
	for expectedCount := int32(1); expectedCount <= 5; expectedCount++ {
		publishing := rh.PrepareRetry(msg, "test_queue")
		
		actualCount, ok := publishing.Headers[RetryCountHeader].(int32)
		if !ok || actualCount != expectedCount {
			t.Errorf("Retry %d: expected count %d, got %v", expectedCount, expectedCount, actualCount)
		}

		// Use the publishing as the next message
		msg = amqp.Delivery{
			Body:    publishing.Body,
			Headers: publishing.Headers,
		}
	}

	// After 5 retries, should not retry anymore
	if rh.ShouldRetry(msg) {
		t.Error("Should not retry after 5 attempts")
	}
}
