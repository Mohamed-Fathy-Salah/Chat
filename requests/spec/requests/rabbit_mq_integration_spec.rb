require 'rails_helper'

RSpec.describe 'RabbitMQ Integration', type: :request do
  let(:user) { create(:user) }
  let(:auth_token) { AuthenticationService.generate_token(user.id) }
  let(:application) { create(:application, creator: user) }

  before do
    cookies.signed[:auth_token] = auth_token
    allow(REDIS).to receive(:incr).and_return(1)
  end

  describe 'Chat creation message publishing' do
    it 'publishes chat creation message to RabbitMQ' do
      expect(RabbitMqService).to receive(:publish).with(
        'create_chats',
        hash_including(
          'application_id' => application.id,
          'token' => application.token,
          'number' => 1,
          'creator_id' => user.id
        )
      )
      
      post "/api/v1/applications/#{application.token}/chats"
      expect(response).to have_http_status(:ok)
    end

    it 'includes all required fields in chat message' do
      message_payload = nil
      allow(RabbitMqService).to receive(:publish) do |queue, payload|
        message_payload = JSON.parse(payload) if queue == 'create_chats'
      end
      
      post "/api/v1/applications/#{application.token}/chats"
      
      expect(message_payload).to include(
        'application_id',
        'token',
        'number',
        'creator_id'
      )
    end

    it 'continues even if RabbitMQ publish fails' do
      allow(RabbitMqService).to receive(:publish).and_raise(StandardError.new('RabbitMQ down'))
      allow(Rails.logger).to receive(:error)
      
      expect {
        post "/api/v1/applications/#{application.token}/chats"
      }.not_to raise_error
    end
  end

  describe 'Message creation publishing' do
    let(:chat) { create(:chat, application: application, creator: user, number: 1) }

    it 'publishes message creation to RabbitMQ' do
      expect(RabbitMqService).to receive(:publish).with(
        'create_messages',
        hash_including(
          'chat_id' => chat.id,
          'token' => application.token,
          'chat_number' => chat.number,
          'number' => 1,
          'body' => 'Test message',
          'creator_id' => user.id
        )
      )
      
      post "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
           params: { body: 'Test message' }
      expect(response).to have_http_status(:ok)
    end

    it 'includes message body in payload' do
      message_payload = nil
      allow(RabbitMqService).to receive(:publish) do |queue, payload|
        message_payload = JSON.parse(payload) if queue == 'create_messages'
      end
      
      post "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
           params: { body: 'Hello World!' }
      
      expect(message_payload['body']).to eq('Hello World!')
    end
  end

  describe 'Message update publishing' do
    let(:chat) { create(:chat, application: application, creator: user, number: 1) }
    let(:message) { create(:message, chat: chat, creator: user, body: 'Original', number: 1) }

    it 'publishes message update to RabbitMQ' do
      expect(RabbitMqService).to receive(:publish).with(
        'update_messages',
        hash_including(
          'token' => application.token,
          'chat_number' => chat.number,
          'number' => message.number,
          'body' => 'Updated body'
        )
      )
      
      put "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
          params: { messageNumber: message.number, body: 'Updated body' }
      expect(response).to have_http_status(:ok)
    end

    it 'publishes updated body to queue' do
      message_payload = nil
      allow(RabbitMqService).to receive(:publish) do |queue, payload|
        message_payload = JSON.parse(payload) if queue == 'update_messages'
      end
      
      put "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
          params: { messageNumber: message.number, body: 'New content' }
      
      expect(message_payload['body']).to eq('New content')
    end

    it 'continues even if publish fails' do
      allow(RabbitMqService).to receive(:publish).and_raise(StandardError.new('RabbitMQ error'))
      allow(Rails.logger).to receive(:error)
      
      expect {
        put "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
            params: { messageNumber: message.number, body: 'Updated' }
      }.not_to raise_error
    end
  end

  describe 'Message format validation' do
    let(:chat) { create(:chat, application: application, creator: user, number: 1) }

    it 'publishes valid JSON' do
      published_message = nil
      allow(RabbitMqService).to receive(:publish) do |_queue, payload|
        published_message = payload
      end
      
      post "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
           params: { body: 'Test message' }
      
      expect { JSON.parse(published_message) }.not_to raise_error
    end

    it 'escapes special characters in JSON' do
      published_message = nil
      allow(RabbitMqService).to receive(:publish) do |_queue, payload|
        published_message = payload
      end
      
      post "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
           params: { body: 'Message with "quotes" and \n newlines' }
      
      parsed = JSON.parse(published_message)
      expect(parsed['body']).to include('"quotes"')
    end
  end

  describe 'Queue names' do
    let(:chat) { create(:chat, application: application, creator: user, number: 1) }

    it 'uses create_chats queue for chat creation' do
      expect(RabbitMqService).to receive(:publish).with('create_chats', anything)
      post "/api/v1/applications/#{application.token}/chats"
    end

    it 'uses create_messages queue for message creation' do
      expect(RabbitMqService).to receive(:publish).with('create_messages', anything)
      post "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
           params: { body: 'Test' }
    end

    it 'uses update_messages queue for message updates' do
      message = create(:message, chat: chat, creator: user, number: 1)
      expect(RabbitMqService).to receive(:publish).with('update_messages', anything)
      put "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
          params: { messageNumber: message.number, body: 'Updated' }
    end
  end
end
