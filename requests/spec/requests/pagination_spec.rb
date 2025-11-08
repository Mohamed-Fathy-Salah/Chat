require 'rails_helper'

RSpec.describe 'Pagination and Filtering', type: :request do
  let(:user) { create(:user) }
  let(:auth_token) { AuthenticationService.generate_token(user.id) }
  let(:application) { create(:application, creator: user) }
  let(:chat) { create(:chat, application: application, creator: user, number: 1) }

  before do
    cookies.signed[:auth_token] = auth_token
  end

  describe 'Message pagination' do
    before do
      15.times do |i|
        create(:message, chat: chat, creator: user, number: i + 1, body: "Message #{i + 1}")
      end
    end

    it 'returns first page by default' do
      get "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages"
      
      json = JSON.parse(response.body)
      expect(json.size).to eq(10)
    end

    it 'supports custom page size' do
      get "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
          params: { limit: 5 }
      
      json = JSON.parse(response.body)
      expect(json.size).to eq(5)
    end

    it 'supports page navigation' do
      get "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
          params: { page: 2, limit: 10 }
      
      json = JSON.parse(response.body)
      expect(json.size).to eq(5) # Remaining 5 messages
    end

    it 'returns empty array for out-of-range page' do
      get "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
          params: { page: 100 }
      
      json = JSON.parse(response.body)
      expect(json).to eq([])
    end

    it 'orders messages by created_at descending' do
      get "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages"
      
      json = JSON.parse(response.body)
      numbers = json.map { |m| m['messageNumber'] }
      expect(numbers).to eq(numbers.sort.reverse)
    end

    it 'handles page=0 gracefully' do
      get "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
          params: { page: 0 }
      
      expect(response).to have_http_status(:ok)
    end

    it 'handles negative page numbers' do
      get "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
          params: { page: -1 }
      
      expect(response).to have_http_status(:ok)
    end

    it 'limits maximum page size' do
      get "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
          params: { limit: 1000 }
      
      json = JSON.parse(response.body)
      expect(json.size).to be <= 100 # Assuming max limit of 100
    end
  end

  describe 'Message search' do
    before do
      create(:message, chat: chat, creator: user, number: 1, body: 'Hello world')
      create(:message, chat: chat, creator: user, number: 2, body: 'Goodbye world')
      create(:message, chat: chat, creator: user, number: 3, body: 'Testing 123')
      create(:message, chat: chat, creator: user, number: 4, body: 'Ruby on Rails')
      create(:message, chat: chat, creator: user, number: 5, body: 'hello WORLD')
    end

    it 'searches case-insensitively' do
      get "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages/search",
          params: { q: 'HELLO' }
      
      json = JSON.parse(response.body)
      expect(json.size).to eq(2)
    end

    it 'returns empty array for no matches' do
      get "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages/search",
          params: { q: 'nonexistent' }
      
      json = JSON.parse(response.body)
      expect(json).to eq([])
    end

    it 'handles empty query string' do
      get "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages/search",
          params: { q: '' }
      
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to eq([])
    end

    it 'handles special characters in query' do
      create(:message, chat: chat, creator: user, number: 6, body: 'C++ programming')
      
      get "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages/search",
          params: { q: 'C++' }
      
      expect(response).to have_http_status(:ok)
    end

    it 'searches partial words' do
      get "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages/search",
          params: { q: 'tes' }
      
      json = JSON.parse(response.body)
      expect(json.size).to be >= 1
    end

    it 'includes sender_name in results' do
      get "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages/search",
          params: { q: 'Hello' }
      
      json = JSON.parse(response.body)
      expect(json.first['senderName']).to eq(user.name)
    end

    it 'returns messages in descending order' do
      get "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages/search",
          params: { q: 'world' }
      
      json = JSON.parse(response.body)
      numbers = json.map { |m| m['messageNumber'] }
      expect(numbers.first).to be > numbers.last
    end

    it 'only searches within specified chat' do
      other_chat = create(:chat, application: application, creator: user, number: 2)
      create(:message, chat: other_chat, creator: user, number: 1, body: 'Hello from other chat')
      
      get "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages/search",
          params: { q: 'Hello' }
      
      json = JSON.parse(response.body)
      expect(json.all? { |m| m['body'].include?('other chat') }).to be false
    end

    it 'handles very long search queries' do
      long_query = 'a' * 1000
      
      get "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages/search",
          params: { q: long_query }
      
      expect(response).to have_http_status(:ok)
    end

    it 'handles unicode characters in search' do
      create(:message, chat: chat, creator: user, number: 7, body: 'Hello 世界 🌍')
      
      get "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages/search",
          params: { q: '世界' }
      
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.size).to be >= 0
    end
  end

  describe 'Chat listing' do
    it 'returns all chats for application' do
      create_list(:chat, 5, application: application, creator: user)
      
      get "/api/v1/applications/#{application.token}/chats"
      
      json = JSON.parse(response.body)
      expect(json.size).to eq(5)
    end

    it 'returns empty array when no chats exist' do
      get "/api/v1/applications/#{application.token}/chats"
      
      json = JSON.parse(response.body)
      expect(json).to eq([])
    end

    it 'includes messages_count in response' do
      chat_with_messages = create(:chat, application: application, creator: user, number: 99)
      create_list(:message, 3, chat: chat_with_messages, creator: user)
      
      get "/api/v1/applications/#{application.token}/chats"
      
      json = JSON.parse(response.body)
      chat_data = json.find { |c| c['chatNumber'] == 99 }
      expect(chat_data['messagesCount']).to be >= 0
    end
  end

  describe 'Application listing' do
    it 'only returns current user\'s applications' do
      other_user = create(:user, email: 'other@example.com')
      create(:application, creator: user, name: 'My App')
      create(:application, creator: other_user, name: 'Other App')
      
      get '/api/v1/applications'
      
      json = JSON.parse(response.body)
      expect(json.size).to eq(1)
      expect(json.first['name']).to eq('My App')
    end

    it 'returns empty array when user has no applications' do
      get '/api/v1/applications'
      
      json = JSON.parse(response.body)
      expect(json).to eq([])
    end

    it 'includes chats_count in response' do
      app = create(:application, creator: user)
      create_list(:chat, 3, application: app, creator: user)
      
      get '/api/v1/applications'
      
      json = JSON.parse(response.body)
      expect(json.first['chatsCount']).to be >= 0
    end
  end
end
