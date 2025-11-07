package config

import "os"

type Config struct {
	DatabaseHost     string
	DatabaseUser     string
	DatabasePassword string
	DatabaseName     string
	RedisURL         string
	RabbitMQURL      string
}

func Load() *Config {
	return &Config{
		DatabaseHost:     getEnv("DATABASE_HOST", "db"),
		DatabaseUser:     getEnv("DATABASE_USERNAME", "root"),
		DatabasePassword: getEnv("DATABASE_PASSWORD", "password"),
		DatabaseName:     getEnv("DATABASE_NAME", "auth_api_development"),
		RedisURL:         getEnv("REDIS_URL", "redis://redis:6379/0"),
		RabbitMQURL:      getEnv("RABBITMQ_URL", "amqp://guest:guest@rabbitmq:5672/"),
	}
}

func getEnv(key, defaultValue string) string {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value
}
