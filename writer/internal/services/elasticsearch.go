package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"

	"github.com/chat/writer/internal/database"
	"github.com/elastic/go-elasticsearch/v8/esapi"
)

type ElasticsearchService struct {
	client *database.ElasticsearchClient
	ctx    context.Context
}

type MessageDocument struct {
	ID         int    `json:"id"`
	Token      string `json:"token"`
	ChatNumber int    `json:"chat_number"`
	Number     int    `json:"number"`
	Body       string `json:"body"`
	SenderID   int    `json:"sender_id"`
	SenderName string `json:"sender_name,omitempty"`
	CreatedAt  string `json:"created_at"`
}

func NewElasticsearchService(client *database.ElasticsearchClient, ctx context.Context) *ElasticsearchService {
	es := &ElasticsearchService{
		client: client,
		ctx:    ctx,
	}

	// Create index if it doesn't exist
	es.createIndexIfNotExists()

	return es
}

func (es *ElasticsearchService) createIndexIfNotExists() {
	indexName := "messages"

	// Check if index exists
	req := esapi.IndicesExistsRequest{
		Index: []string{indexName},
	}

	res, err := req.Do(es.ctx, es.client)
	if err != nil {
		log.Printf("Error checking if index exists: %v", err)
		return
	}
	defer res.Body.Close()

	// Index already exists
	if res.StatusCode == 200 {
		return
	}

	// Create index with mapping and n-gram support for partial word matching
	mapping := `{
		"settings": {
			"analysis": {
				"analyzer": {
					"ngram_analyzer": {
						"type": "custom",
						"tokenizer": "standard",
						"filter": ["lowercase", "ngram_filter"]
					},
					"search_analyzer": {
						"type": "custom",
						"tokenizer": "standard",
						"filter": ["lowercase"]
					}
				},
				"filter": {
					"ngram_filter": {
						"type": "edge_ngram",
						"min_gram": 3,
						"max_gram": 20
					}
				}
			}
		},
		"mappings": {
			"properties": {
				"id": { "type": "integer" },
				"token": { "type": "keyword" },
				"chat_number": { "type": "integer" },
				"number": { "type": "integer" },
				"body": { 
					"type": "text",
					"analyzer": "ngram_analyzer",
					"search_analyzer": "search_analyzer",
					"fields": {
						"keyword": { "type": "keyword" },
						"exact": { "type": "text", "analyzer": "standard" }
					}
				},
				"sender_id": { "type": "integer" },
				"sender_name": { "type": "keyword" },
				"created_at": { "type": "date" }
			}
		}
	}`

	createReq := esapi.IndicesCreateRequest{
		Index: indexName,
		Body:  strings.NewReader(mapping),
	}

	createRes, err := createReq.Do(es.ctx, es.client)
	if err != nil {
		log.Printf("Error creating index: %v", err)
		return
	}
	defer createRes.Body.Close()

	if createRes.IsError() {
		log.Printf("Error creating index: %s", createRes.String())
	} else {
		log.Println("Created Elasticsearch index: messages")
	}
}

func (es *ElasticsearchService) IndexMessage(doc MessageDocument) error {
	// Create document ID from token:chat_number:message_number
	docID := fmt.Sprintf("%s:%d:%d", doc.Token, doc.ChatNumber, doc.Number)

	data, err := json.Marshal(doc)
	if err != nil {
		return err
	}

	req := esapi.IndexRequest{
		Index:      "messages",
		DocumentID: docID,
		Body:       bytes.NewReader(data),
		Refresh:    "true",
	}

	res, err := req.Do(es.ctx, es.client)
	if err != nil {
		return err
	}
	defer res.Body.Close()

	if res.IsError() {
		return fmt.Errorf("error indexing document: %s", res.String())
	}

	return nil
}

func (es *ElasticsearchService) UpdateMessage(token string, chatNumber int, messageNumber int, body string) error {
	// Create document ID
	docID := fmt.Sprintf("%s:%d:%d", token, chatNumber, messageNumber)

	// Update only the body field
	updateDoc := map[string]any{
		"doc": map[string]interface{}{
			"body": body,
		},
	}

	data, err := json.Marshal(updateDoc)
	if err != nil {
		return err
	}

	req := esapi.UpdateRequest{
		Index:      "messages",
		DocumentID: docID,
		Body:       bytes.NewReader(data),
		Refresh:    "true",
	}

	res, err := req.Do(es.ctx, es.client)
	if err != nil {
		return err
	}
	defer res.Body.Close()

	if res.IsError() {
		return fmt.Errorf("error updating document: %s", res.String())
	}

	return nil
}
