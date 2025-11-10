package models

import "time"

type CreateChatMessage struct {
	Token      string `json:"token"`
	ChatNumber int    `json:"chatNumber"`
	CreatorID  int    `json:"creatorId"`
}

type CreateMessageMessage struct {
	Token         string `json:"token"`
	ChatNumber    int    `json:"chatNumber"`
	MessageNumber int    `json:"messageNumber"`
	SenderID      int    `json:"senderId"`
	Body          string `json:"body"`
	Date          string `json:"date"`
}

type UpdateMessageMessage struct {
	Token         string `json:"token"`
	ChatNumber    int    `json:"chatNumber"`
	MessageNumber int    `json:"messageNumber"`
	Body          string `json:"body"`
}

type Chat struct {
	ID            int
	Token         string
	Number        int
	CreatorID     int
	CreatedAt     time.Time
	UpdatedAt     time.Time
}

type Message struct {
	ID         int
	Token      string
	ChatNumber int
	Number     int
	Body       string
	CreatorID  int
	CreatedAt  time.Time
	UpdatedAt  time.Time
}
