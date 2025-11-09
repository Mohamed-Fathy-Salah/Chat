package cron

import (
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/chat/writer/internal/database"
)

func TestBatchUpdateChatsCount_PreventsSQLInjection(t *testing.T) {
	// Create mock database
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("Failed to create mock: %v", err)
	}
	defer db.Close()

	// Create CountSync with mock DB
	mockDB := &database.DB{DB: db}
	redisClient := &database.RedisClient{} // Not used in this test
	cs := NewCountSync(mockDB, redisClient)

	// Test with malicious token containing SQL injection attempt
	updates := []CountUpdate{
		{Token: "abc123", Count: 5},
		{Token: "xyz'; DROP TABLE applications; --", Count: 10}, // SQL injection attempt
		{Token: "normal_token", Count: 3},
	}

	// Expect parameterized query
	expectedQuery := `
		UPDATE applications
		SET chats_count = CASE token
			WHEN \? THEN \? WHEN \? THEN \? WHEN \? THEN \?
		END
		WHERE token IN \(\?, \?, \?\)
	`

	mock.ExpectExec(expectedQuery).
		WithArgs(
			"abc123", 5,
			"xyz'; DROP TABLE applications; --", 10,
			"normal_token", 3,
			"abc123",
			"xyz'; DROP TABLE applications; --",
			"normal_token",
		).
		WillReturnResult(sqlmock.NewResult(0, 3))

	err = cs.batchUpdateChatsCount(updates)
	if err != nil {
		t.Errorf("Expected no error, got: %v", err)
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("Unfulfilled expectations: %v", err)
	}
}

func TestBatchUpdateMessagesCount_PreventsSQLInjection(t *testing.T) {
	// Create mock database
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("Failed to create mock: %v", err)
	}
	defer db.Close()

	// Create CountSync with mock DB
	mockDB := &database.DB{DB: db}
	redisClient := &database.RedisClient{} // Not used in this test
	cs := NewCountSync(mockDB, redisClient)

	// Test with malicious token containing SQL injection attempt
	updates := []messageUpdate{
		{token: "abc123", chatNumber: 1, count: 5},
		{token: "xyz'; DELETE FROM chats; --", chatNumber: 2, count: 10}, // SQL injection attempt
		{token: "normal_token", chatNumber: 3, count: 3},
	}

	// Expect parameterized query
	expectedQuery := `
		UPDATE chats
		SET messages_count = CASE
			WHEN token = \? AND number = \? THEN \? WHEN token = \? AND number = \? THEN \? WHEN token = \? AND number = \? THEN \?
		END
		WHERE \(token = \? AND number = \?\) OR \(token = \? AND number = \?\) OR \(token = \? AND number = \?\)
	`

	mock.ExpectExec(expectedQuery).
		WithArgs(
			// CASE clause args
			"abc123", 1, 5,
			"xyz'; DELETE FROM chats; --", 2, 10,
			"normal_token", 3, 3,
			// WHERE clause args
			"abc123", 1,
			"xyz'; DELETE FROM chats; --", 2,
			"normal_token", 3,
		).
		WillReturnResult(sqlmock.NewResult(0, 3))

	err = cs.batchUpdateMessagesCount(updates)
	if err != nil {
		t.Errorf("Expected no error, got: %v", err)
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("Unfulfilled expectations: %v", err)
	}
}

func TestBatchUpdateChatsCount_EmptyUpdates(t *testing.T) {
	// Create mock database
	db, _, err := sqlmock.New()
	if err != nil {
		t.Fatalf("Failed to create mock: %v", err)
	}
	defer db.Close()

	mockDB := &database.DB{DB: db}
	redisClient := &database.RedisClient{}
	cs := NewCountSync(mockDB, redisClient)

	// Empty updates should not execute query
	updates := []CountUpdate{}

	err = cs.batchUpdateChatsCount(updates)
	if err != nil {
		t.Errorf("Expected no error for empty updates, got: %v", err)
	}
}

func TestBatchUpdateMessagesCount_EmptyUpdates(t *testing.T) {
	// Create mock database
	db, _, err := sqlmock.New()
	if err != nil {
		t.Fatalf("Failed to create mock: %v", err)
	}
	defer db.Close()

	mockDB := &database.DB{DB: db}
	redisClient := &database.RedisClient{}
	cs := NewCountSync(mockDB, redisClient)

	// Empty updates should not execute query
	updates := []messageUpdate{}

	err = cs.batchUpdateMessagesCount(updates)
	if err != nil {
		t.Errorf("Expected no error for empty updates, got: %v", err)
	}
}

func TestBatchUpdateChatsCount_SpecialCharacters(t *testing.T) {
	// Create mock database
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("Failed to create mock: %v", err)
	}
	defer db.Close()

	mockDB := &database.DB{DB: db}
	redisClient := &database.RedisClient{}
	cs := NewCountSync(mockDB, redisClient)

	// Test with various special characters that could cause issues
	updates := []CountUpdate{
		{Token: "token-with-dash", Count: 1},
		{Token: "token_with_underscore", Count: 2},
		{Token: "token'with'quotes", Count: 3},
		{Token: "token\"with\"doublequotes", Count: 4},
		{Token: "token\\with\\backslash", Count: 5},
	}

	expectedQuery := `
		UPDATE applications
		SET chats_count = CASE token
			WHEN \? THEN \? WHEN \? THEN \? WHEN \? THEN \? WHEN \? THEN \? WHEN \? THEN \?
		END
		WHERE token IN \(\?, \?, \?, \?, \?\)
	`

	mock.ExpectExec(expectedQuery).
		WithArgs(
			"token-with-dash", 1,
			"token_with_underscore", 2,
			"token'with'quotes", 3,
			"token\"with\"doublequotes", 4,
			"token\\with\\backslash", 5,
			"token-with-dash",
			"token_with_underscore",
			"token'with'quotes",
			"token\"with\"doublequotes",
			"token\\with\\backslash",
		).
		WillReturnResult(sqlmock.NewResult(0, 5))

	err = cs.batchUpdateChatsCount(updates)
	if err != nil {
		t.Errorf("Expected no error, got: %v", err)
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("Unfulfilled expectations: %v", err)
	}
}
