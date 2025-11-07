require 'rails_helper'

RSpec.describe 'Api::V1::Applications', type: :request do
  let(:user) { create(:user) }
  let(:auth_token) { AuthenticationService.generate_token(user.id) }
  
  before do
    cookies.signed[:auth_token] = auth_token
  end

  describe 'POST /api/v1/applications' do
    it 'creates a new application' do
      post '/api/v1/applications', params: { name: 'Test App' }
      
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['token']).to be_present
    end
  end

  describe 'GET /api/v1/applications' do
    it 'returns all applications for the current user' do
      create_list(:application, 3, creator: user)
      
      get '/api/v1/applications'
      
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.size).to eq(3)
    end
  end

  describe 'PUT /api/v1/applications' do
    it 'updates an application' do
      application = create(:application, creator: user)
      
      put '/api/v1/applications', params: { token: application.token, name: 'Updated App' }
      
      expect(response).to have_http_status(:ok)
      expect(application.reload.name).to eq('Updated App')
    end
  end
end
