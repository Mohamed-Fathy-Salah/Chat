package database

import (
	"database/sql"
	"fmt"
	"log"
	"time"

	_ "github.com/go-sql-driver/mysql"
)

type DB struct {
	*sql.DB
}

func Connect(host, user, password, dbName string) (*DB, error) {
	dsn := fmt.Sprintf("%s:%s@tcp(%s:3306)/%s?parseTime=true", user, password, host, dbName)

	var db *sql.DB
	var err error

	// Retry connection
	for i := 0; i < 10; i++ {
		db, err = sql.Open("mysql", dsn)
		if err == nil {
			err = db.Ping()
			if err == nil {
				// Configure connection pool for high throughput
				db.SetMaxOpenConns(50)
				db.SetMaxIdleConns(25)
				db.SetConnMaxLifetime(5 * time.Minute)
				db.SetConnMaxIdleTime(2 * time.Minute)
				
				log.Println("Connected to MySQL with connection pool configured")
				return &DB{db}, nil
			}
		}
		log.Printf("Failed to connect to MySQL, retrying in 2s... (%d/10)", i+1)
		time.Sleep(2 * time.Second)
	}

	return nil, err
}
