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

// DeclareQueueWithDLQ declares a queue with dead letter exchange configured
func (r *RabbitMQ) DeclareQueueWithDLQ(ch *amqp.Channel, queueName string) (amqp.Queue, error) {
	dlxName := queueName + ".dlx"
	dlqName := queueName + ".dlq"

	// Declare dead letter exchange
	err := ch.ExchangeDeclare(
		dlxName,  // name
		"fanout", // type
		true,     // durable
		false,    // auto-deleted
		false,    // internal
		false,    // no-wait
		nil,      // arguments
	)
	if err != nil {
		return amqp.Queue{}, err
	}

	// Declare dead letter queue
	_, err = ch.QueueDeclare(
		dlqName, // name
		true,    // durable
		false,   // delete when unused
		false,   // exclusive
		false,   // no-wait
		nil,     // arguments
	)
	if err != nil {
		return amqp.Queue{}, err
	}

	// Bind DLQ to DLX
	err = ch.QueueBind(
		dlqName, // queue name
		"",      // routing key
		dlxName, // exchange
		false,   // no-wait
		nil,     // arguments
	)
	if err != nil {
		return amqp.Queue{}, err
	}

	// Declare main queue with DLX configured
	return ch.QueueDeclare(
		queueName, // name
		true,      // durable
		false,     // delete when unused
		false,     // exclusive
		false,     // no-wait
		amqp.Table{
			"x-dead-letter-exchange": dlxName,
		},
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
