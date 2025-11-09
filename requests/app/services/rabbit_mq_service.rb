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
    # Don't declare queue here - let the consumer (writer service) handle it
    # This avoids queue configuration conflicts
    
    channel.default_exchange.publish(
      message,
      routing_key: queue_name,
      persistent: true,
      content_type: 'application/json'
    )
  rescue StandardError => e
    Rails.logger.error "Failed to publish to RabbitMQ: #{e.message}"
    raise
  end

  def self.close
    @channel&.close
    @connection&.close
  end
end
