package database

import (
	"context"
	"log"

	"github.com/redis/go-redis/v9"
)

type RedisClient struct {
	*redis.Client
	ctx context.Context
}

func ConnectRedis(redisURL string, ctx context.Context) (*RedisClient, error) {
	opt, err := redis.ParseURL(redisURL)
	if err != nil {
		return nil, err
	}

	client := redis.NewClient(opt)

	_, err = client.Ping(ctx).Result()
	if err != nil {
		return nil, err
	}

	log.Println("Connected to Redis")
	return &RedisClient{
		Client: client,
		ctx:    ctx,
	}, nil
}

func (r *RedisClient) GetInt(key string) (int, error) {
	return r.Get(r.ctx, key).Int()
}

func (r *RedisClient) GetString(key string) (string, error) {
	return r.Get(r.ctx, key).Result()
}

func (r *RedisClient) SetString(key, value string) error {
	return r.Set(r.ctx, key, value, 0).Err()
}

func (r *RedisClient) Context() context.Context {
	return r.ctx
}

func (r *RedisClient) SAdd(key string, members ...any) error {
	return r.Client.SAdd(r.ctx, key, members...).Err()
}

func (r *RedisClient) SMembers(key string) ([]string, error) {
	return r.Client.SMembers(r.ctx, key).Result()
}

func (r *RedisClient) Del(keys ...string) error {
	return r.Client.Del(r.ctx, keys...).Err()
}
