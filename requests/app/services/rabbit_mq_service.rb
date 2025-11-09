require 'bunny'

class RabbitMqService
  def self.connection
    @connection ||= Bunny.new(ENV['RABBITMQ_URL'] || 'amqp://guest:guest@rabbitmq:5672')
    @connection.start unless @connection.open?
    @connection
  end

  def self.channel
    @channel ||= connection.create_channel
  end

  def self.publish(queue_name, message)
    # Declare queue with DLX configuration to match writer service
    dlx_name = "#{queue_name}.dlx"
    
    # Declare queue with dead letter exchange (matches writer Go service)
    queue = channel.queue(queue_name, 
      durable: true,
      arguments: {
        'x-dead-letter-exchange' => dlx_name
      }
    )
    
    channel.default_exchange.publish(
      message,
      routing_key: queue.name,
      persistent: true,
      content_type: 'application/json'
    )
  rescue StandardError => e
    Rails.logger.error "Failed to publish to RabbitMQ: #{e.message}"
  end

  def self.close
    @channel&.close
    @connection&.close
  end
end
