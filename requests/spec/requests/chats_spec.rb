require 'rails_helper'

RSpec.describe 'Api::V1::Chats', type: :request do
  let(:user) { create(:user) }
  let(:application) { create(:application, creator: user) }
  let(:auth_token) { AuthenticationService.generate_token(user.id) }
  
  before do
    cookies.signed[:auth_token] = auth_token
    allow(REDIS).to receive(:incr).and_return(1)
  end

  describe 'POST /api/v1/applications/:token/chats' do
    it 'creates a new chat' do
      post "/api/v1/applications/#{application.token}/chats"
      
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['chatNumber']).to be_present
    end
  end

  describe 'GET /api/v1/applications/:token/chats' do
    it 'returns all chats for the application' do
      create_list(:chat, 3, application: application, creator: user)
      
      get "/api/v1/applications/#{application.token}/chats"
      
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.size).to eq(3)
    end
  end
end
