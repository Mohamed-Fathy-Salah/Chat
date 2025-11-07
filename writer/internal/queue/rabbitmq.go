package queue

import (
	"log"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
)

type RabbitMQ struct {
	conn *amqp.Connection
}

func Connect(url string) (*RabbitMQ, error) {
	var conn *amqp.Connection
	var err error

	// Retry connection
	for i := 0; i < 10; i++ {
		conn, err = amqp.Dial(url)
		if err == nil {
			log.Println("Connected to RabbitMQ")
			return &RabbitMQ{conn: conn}, nil
		}
		log.Printf("Failed to connect to RabbitMQ, retrying in 2s... (%d/10)", i+1)
		time.Sleep(2 * time.Second)
	}

	return nil, err
}

func (r *RabbitMQ) Close() error {
	return r.conn.Close()
}

func (r *RabbitMQ) CreateChannel() (*amqp.Channel, error) {
	return r.conn.Channel()
}

func (r *RabbitMQ) DeclareQueue(ch *amqp.Channel, queueName string) (amqp.Queue, error) {
	return ch.QueueDeclare(
		queueName, // name
		true,      // durable
		false,     // delete when unused
		false,     // exclusive
		false,     // no-wait
		nil,       // arguments
	)
}

func (r *RabbitMQ) Consume(ch *amqp.Channel, queueName string) (<-chan amqp.Delivery, error) {
	return ch.Consume(
		queueName, // queue
		"",        // consumer
		false,     // auto-ack
		false,     // exclusive
		false,     // no-local
		false,     // no-wait
		nil,       // args
	)
}
