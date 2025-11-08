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
	ID          int    `json:"id"`
	ChatID      int    `json:"chat_id"`
	Token       string `json:"token"`
	ChatNumber  int    `json:"chat_number"`
	Number      int    `json:"number"`
	Body        string `json:"body"`
	SenderID    int    `json:"sender_id"`
	SenderName  string `json:"sender_name,omitempty"`
	CreatedAt   string `json:"created_at"`
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

	// Create index with mapping
	mapping := `{
		"mappings": {
			"properties": {
				"id": { "type": "integer" },
				"chat_id": { "type": "integer" },
				"token": { "type": "keyword" },
				"chat_number": { "type": "integer" },
				"number": { "type": "integer" },
				"body": { "type": "text" },
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
	updateDoc := map[string]interface{}{
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

func (es *ElasticsearchService) SearchMessages(token string, chatNumber int, query string) ([]MessageDocument, error) {
	// Build search query
	searchQuery := map[string]interface{}{
		"query": map[string]interface{}{
			"bool": map[string]interface{}{
				"must": []map[string]interface{}{
					{
						"term": map[string]interface{}{
							"token": token,
						},
					},
					{
						"term": map[string]interface{}{
							"chat_number": chatNumber,
						},
					},
					{
						"match": map[string]interface{}{
							"body": query,
						},
					},
				},
			},
		},
		"sort": []map[string]interface{}{
			{
				"created_at": map[string]string{
					"order": "desc",
				},
			},
		},
	}

	data, err := json.Marshal(searchQuery)
	if err != nil {
		return nil, err
	}

	res, err := es.client.Search(
		es.client.Search.WithContext(es.ctx),
		es.client.Search.WithIndex("messages"),
		es.client.Search.WithBody(bytes.NewReader(data)),
	)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()

	if res.IsError() {
		return nil, fmt.Errorf("error searching: %s", res.String())
	}

	// Parse response
	var result map[string]interface{}
	if err := json.NewDecoder(res.Body).Decode(&result); err != nil {
		return nil, err
	}

	hits := result["hits"].(map[string]interface{})["hits"].([]interface{})
	
	messages := make([]MessageDocument, 0, len(hits))
	for _, hit := range hits {
		source := hit.(map[string]interface{})["_source"]
		sourceBytes, _ := json.Marshal(source)
		
		var msg MessageDocument
		if err := json.Unmarshal(sourceBytes, &msg); err != nil {
			continue
		}
		messages = append(messages, msg)
	}

	return messages, nil
}
