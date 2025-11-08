package database

import (
	"log"
	"time"

	"github.com/elastic/go-elasticsearch/v8"
)

type ElasticsearchClient struct {
	*elasticsearch.Client
}

func ConnectElasticsearch(url string) (*ElasticsearchClient, error) {
	cfg := elasticsearch.Config{
		Addresses: []string{url},
	}

	var client *elasticsearch.Client
	var err error

	// Retry connection
	for i := 0; i < 10; i++ {
		client, err = elasticsearch.NewClient(cfg)
		if err == nil {
			// Test connection
			res, err := client.Info()
			if err == nil {
				res.Body.Close()
				log.Println("Connected to Elasticsearch")
				return &ElasticsearchClient{client}, nil
			}
		}
		log.Printf("Failed to connect to Elasticsearch, retrying in 2s... (%d/10)", i+1)
		time.Sleep(2 * time.Second)
	}

	return nil, err
}
