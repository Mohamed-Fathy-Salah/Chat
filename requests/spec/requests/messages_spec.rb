require 'rails_helper'

RSpec.describe 'Api::V1::Messages', type: :request do
  let(:user) { create(:user) }
  let(:application) { create(:application, creator: user) }
  let(:chat) { create(:chat, application: application, creator: user) }
  let(:auth_token) { AuthenticationService.generate_token(user.id) }
  
  before do
    cookies.signed[:auth_token] = auth_token
    allow(REDIS).to receive(:incr).and_return(1)
  end

  describe 'POST /api/v1/applications/:token/chats/:chat_number/messages' do
    it 'creates a new message' do
      post "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
           params: { body: 'Test message' }
      
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['messageNumber']).to be_present
    end
  end

  describe 'GET /api/v1/applications/:token/chats/:chat_number/messages' do
    it 'returns all messages for the chat' do
      create_list(:message, 5, chat: chat, creator: user)
      
      get "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages"
      
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.size).to eq(5)
    end
  end

  describe 'PUT /api/v1/applications/:token/chats/:chat_number/messages' do
    it 'updates a message' do
      message = create(:message, chat: chat, creator: user)
      
      put "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
          params: { messageNumber: message.number, body: 'Updated message' }
      
      expect(response).to have_http_status(:ok)
      expect(message.reload.body).to eq('Updated message')
    end
  end

  describe 'GET /api/v1/applications/:token/chats/:chat_number/messages/search' do
    it 'searches messages' do
      create(:message, chat: chat, creator: user, body: 'Hello world')
      create(:message, chat: chat, creator: user, body: 'Goodbye world')
      
      get "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages/search",
          params: { q: 'Hello' }
      
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.size).to eq(1)
    end
  end
end
