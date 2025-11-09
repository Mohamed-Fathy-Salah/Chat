require 'rails_helper'

RSpec.describe 'Race Condition Protection', type: :request do
  let(:user) { create(:user) }
  let(:auth_token) { AuthenticationService.generate_token(user.id) }
  let(:application) { create(:application, creator: user, chats_count: 0) }

  before do
    cookies.signed[:auth_token] = auth_token
    # Clear Redis to test initialization
    REDIS.flushdb
  end

  describe 'Chat counter race condition' do
    it 'generates unique chat numbers under concurrent requests' do
      # Simulate 10 concurrent requests
      threads = 10.times.map do |i|
        Thread.new do
          post "/api/v1/applications/#{application.token}/chats"
          JSON.parse(response.body)['chatNumber']
        end
      end
      
      chat_numbers = threads.map(&:value)
      
      # All chat numbers should be unique
      expect(chat_numbers.uniq.size).to eq(10)
      expect(chat_numbers.sort).to eq((1..10).to_a)
    end

    it 'correctly initializes counter from database' do
      # Set initial count in database
      application.update!(chats_count: 5)
      
      # First request should start from 6
      post "/api/v1/applications/#{application.token}/chats"
      json = JSON.parse(response.body)
      expect(json['chatNumber']).to eq(6)
      
      # Second request should be 7
      post "/api/v1/applications/#{application.token}/chats"
      json = JSON.parse(response.body)
      expect(json['chatNumber']).to eq(7)
    end

    it 'handles race condition during initialization' do
      application.update!(chats_count: 10)
      REDIS.flushdb
      
      # Simulate race: both threads try to initialize simultaneously
      barrier = Concurrent::CyclicBarrier.new(2)
      
      threads = 2.times.map do
        Thread.new do
          barrier.wait # Synchronize start
          post "/api/v1/applications/#{application.token}/chats"
          JSON.parse(response.body)['chatNumber']
        end
      end
      
      results = threads.map(&:value)
      
      # Should get 11 and 12, not duplicate values
      expect(results.sort).to eq([11, 12])
    end
  end

  describe 'Message counter race condition' do
    let(:chat) { create(:chat, application: application, creator: user, number: 1, messages_count: 0) }

    it 'generates unique message numbers under concurrent requests' do
      # Simulate 10 concurrent requests
      threads = 10.times.map do
        Thread.new do
          post "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
               params: { body: 'Test message' }
          JSON.parse(response.body)['messageNumber']
        end
      end
      
      message_numbers = threads.map(&:value)
      
      # All message numbers should be unique
      expect(message_numbers.uniq.size).to eq(10)
      expect(message_numbers.sort).to eq((1..10).to_a)
    end

    it 'correctly initializes counter from database' do
      chat.update!(messages_count: 5)
      REDIS.flushdb
      
      # First request should start from 6
      post "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
           params: { body: 'Test message' }
      json = JSON.parse(response.body)
      expect(json['messageNumber']).to eq(6)
      
      # Second request should be 7
      post "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
           params: { body: 'Test message 2' }
      json = JSON.parse(response.body)
      expect(json['messageNumber']).to eq(7)
    end

    it 'handles race condition during initialization' do
      chat.update!(messages_count: 10)
      REDIS.flushdb
      
      # Simulate race: both threads try to initialize simultaneously
      barrier = Concurrent::CyclicBarrier.new(2)
      
      threads = 2.times.map do
        Thread.new do
          barrier.wait # Synchronize start
          post "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
               params: { body: 'Test message' }
          JSON.parse(response.body)['messageNumber']
        end
      end
      
      results = threads.map(&:value)
      
      # Should get 11 and 12, not duplicate values
      expect(results.sort).to eq([11, 12])
    end
  end

  describe 'Redis counter persistence' do
    it 'tracks changes for batch sync' do
      # Create a chat
      post "/api/v1/applications/#{application.token}/chats"
      
      # Verify change tracking
      changes = REDIS.smembers('chat_changes')
      expect(changes).to include(application.token)
    end

    it 'tracks message changes for batch sync' do
      chat = create(:chat, application: application, creator: user, number: 1)
      
      # Create a message
      post "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
           params: { body: 'Test' }
      
      # Verify change tracking
      changes = REDIS.smembers('message_changes')
      expect(changes).to include("#{application.token}:#{chat.number}")
    end
  end
end
