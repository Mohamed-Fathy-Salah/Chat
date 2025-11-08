require 'rails_helper'

RSpec.describe RabbitMqService do
  let(:mock_connection) { instance_double(Bunny::Session) }
  let(:mock_channel) { instance_double(Bunny::Channel) }
  let(:mock_queue) { instance_double(Bunny::Queue, name: 'test_queue') }
  let(:mock_exchange) { instance_double(Bunny::Exchange) }

  before do
    # Reset class variables
    RabbitMqService.instance_variable_set(:@connection, nil)
    RabbitMqService.instance_variable_set(:@channel, nil)
  end

  describe '.connection' do
    it 'creates a new connection if none exists' do
      expect(Bunny).to receive(:new).with(ENV['RABBITMQ_URL'] || 'amqp://guest:guest@rabbitmq:5672').and_return(mock_connection)
      expect(mock_connection).to receive(:open?).and_return(false)
      expect(mock_connection).to receive(:start)
      
      connection = RabbitMqService.connection
      expect(connection).to eq(mock_connection)
    end

    it 'reuses existing open connection' do
      RabbitMqService.instance_variable_set(:@connection, mock_connection)
      expect(mock_connection).to receive(:open?).and_return(true)
      
      connection = RabbitMqService.connection
      expect(connection).to eq(mock_connection)
    end

    it 'starts connection if closed' do
      RabbitMqService.instance_variable_set(:@connection, mock_connection)
      expect(mock_connection).to receive(:open?).and_return(false)
      expect(mock_connection).to receive(:start)
      
      RabbitMqService.connection
    end
  end

  describe '.channel' do
    it 'creates a channel from connection' do
      allow(RabbitMqService).to receive(:connection).and_return(mock_connection)
      expect(mock_connection).to receive(:create_channel).and_return(mock_channel)
      
      channel = RabbitMqService.channel
      expect(channel).to eq(mock_channel)
    end

    it 'reuses existing channel' do
      RabbitMqService.instance_variable_set(:@channel, mock_channel)
      
      channel = RabbitMqService.channel
      expect(channel).to eq(mock_channel)
    end
  end

  describe '.publish' do
    let(:test_message) { { id: 1, data: 'test' }.to_json }

    before do
      allow(RabbitMqService).to receive(:channel).and_return(mock_channel)
      allow(mock_channel).to receive(:queue).with('test_queue', durable: true).and_return(mock_queue)
      allow(mock_channel).to receive(:default_exchange).and_return(mock_exchange)
    end

    it 'publishes message to queue' do
      expect(mock_exchange).to receive(:publish).with(
        test_message,
        routing_key: 'test_queue',
        persistent: true,
        content_type: 'application/json'
      )
      
      RabbitMqService.publish('test_queue', test_message)
    end

    it 'creates a durable queue' do
      expect(mock_channel).to receive(:queue).with('test_queue', durable: true).and_return(mock_queue)
      allow(mock_exchange).to receive(:publish)
      
      RabbitMqService.publish('test_queue', test_message)
    end

    it 'sends persistent messages' do
      expect(mock_exchange).to receive(:publish).with(
        anything,
        hash_including(persistent: true)
      )
      
      RabbitMqService.publish('test_queue', test_message)
    end

    it 'sets content type to application/json' do
      expect(mock_exchange).to receive(:publish).with(
        anything,
        hash_including(content_type: 'application/json')
      )
      
      RabbitMqService.publish('test_queue', test_message)
    end

    it 'logs error on publish failure' do
      allow(mock_exchange).to receive(:publish).and_raise(StandardError.new('Connection lost'))
      
      expect(Rails.logger).to receive(:error).with(/Failed to publish to RabbitMQ/)
      
      RabbitMqService.publish('test_queue', test_message)
    end

    it 'does not raise exception on failure' do
      allow(mock_exchange).to receive(:publish).and_raise(StandardError.new('Connection lost'))
      allow(Rails.logger).to receive(:error)
      
      expect {
        RabbitMqService.publish('test_queue', test_message)
      }.not_to raise_error
    end
  end

  describe '.close' do
    it 'closes channel and connection' do
      RabbitMqService.instance_variable_set(:@channel, mock_channel)
      RabbitMqService.instance_variable_set(:@connection, mock_connection)
      
      expect(mock_channel).to receive(:close)
      expect(mock_connection).to receive(:close)
      
      RabbitMqService.close
    end

    it 'handles nil channel gracefully' do
      RabbitMqService.instance_variable_set(:@channel, nil)
      RabbitMqService.instance_variable_set(:@connection, mock_connection)
      
      expect(mock_connection).to receive(:close)
      
      expect { RabbitMqService.close }.not_to raise_error
    end

    it 'handles nil connection gracefully' do
      RabbitMqService.instance_variable_set(:@channel, mock_channel)
      RabbitMqService.instance_variable_set(:@connection, nil)
      
      expect(mock_channel).to receive(:close)
      
      expect { RabbitMqService.close }.not_to raise_error
    end
  end
end
