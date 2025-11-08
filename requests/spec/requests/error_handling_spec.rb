require 'rails_helper'

RSpec.describe 'API Error Handling', type: :request do
  let(:user) { create(:user) }
  let(:auth_token) { AuthenticationService.generate_token(user.id) }

  describe 'Authentication errors' do
    it 'returns 401 when no auth token provided' do
      get '/api/v1/applications'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 401 for invalid auth token' do
      cookies.signed[:auth_token] = 'invalid_token'
      get '/api/v1/applications'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 401 for expired auth token' do
      expired_token = JWT.encode(
        { user_id: user.id, exp: 1.hour.ago.to_i },
        AuthenticationService.current_secret_key,
        'HS256'
      )
      cookies.signed[:auth_token] = expired_token
      get '/api/v1/applications'
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'Resource not found errors' do
    before { cookies.signed[:auth_token] = auth_token }

    it 'returns 404 for non-existent application' do
      get '/api/v1/applications/non_existent_token/chats'
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for non-existent chat' do
      application = create(:application, creator: user)
      get "/api/v1/applications/#{application.token}/chats/999/messages"
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 when updating non-existent application' do
      put '/api/v1/applications', params: { token: 'non_existent', name: 'New Name' }
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 when updating non-existent message' do
      application = create(:application, creator: user)
      chat = create(:chat, application: application, creator: user)
      
      put "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
          params: { messageNumber: 999, body: 'Updated' }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'Authorization errors' do
    let(:other_user) { create(:user, email: 'other@example.com') }
    let(:other_user_token) { AuthenticationService.generate_token(other_user.id) }

    before { cookies.signed[:auth_token] = other_user_token }

    it 'returns 403 when updating another user\'s application' do
      application = create(:application, creator: user)
      
      put '/api/v1/applications', params: { token: application.token, name: 'Hacked Name' }
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 403 when updating another user\'s message' do
      application = create(:application, creator: user)
      chat = create(:chat, application: application, creator: user)
      message = create(:message, chat: chat, creator: user)
      
      put "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
          params: { messageNumber: message.number, body: 'Hacked' }
      expect(response).to have_http_status(:forbidden)
    end

    it 'allows reading other user\'s public resources' do
      application = create(:application, creator: user)
      
      get "/api/v1/applications/#{application.token}/chats"
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'Validation errors' do
    before { cookies.signed[:auth_token] = auth_token }

    it 'returns 422 when creating application without name' do
      post '/api/v1/applications', params: { name: '' }
      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['errors']).to be_present
    end

    it 'returns 422 when creating message without body' do
      application = create(:application, creator: user)
      chat = create(:chat, application: application, creator: user)
      allow(REDIS).to receive(:incr).and_return(1)
      
      post "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
           params: { body: '' }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'Rate limiting and concurrent requests' do
    before do
      cookies.signed[:auth_token] = auth_token
      allow(REDIS).to receive(:incr).and_return(1, 2, 3)
    end

    it 'handles multiple concurrent chat creations' do
      application = create(:application, creator: user)
      
      threads = 3.times.map do |i|
        Thread.new do
          post "/api/v1/applications/#{application.token}/chats"
          response.status
        end
      end
      
      results = threads.map(&:value)
      expect(results).to all(eq(200))
    end
  end
end
