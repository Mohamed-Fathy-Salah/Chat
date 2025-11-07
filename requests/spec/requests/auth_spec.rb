require 'rails_helper'

RSpec.describe 'Api::V1::Auth', type: :request do
  let(:valid_attributes) do
    {
      user: {
        email: 'test@example.com',
        password: 'password123',
        password_confirmation: 'password123',
        name: 'Test User'
      }
    }
  end

  describe 'POST /api/v1/auth/register' do
    context 'with valid parameters' do
      it 'creates a new user' do
        expect {
          post '/api/v1/auth/register', params: valid_attributes
        }.to change(User, :count).by(1)
      end

      it 'returns created status' do
        post '/api/v1/auth/register', params: valid_attributes
        expect(response).to have_http_status(:created)
      end

      it 'returns user data' do
        post '/api/v1/auth/register', params: valid_attributes
        json = JSON.parse(response.body)
        
        expect(json['user']['email']).to eq('test@example.com')
        expect(json['user']['name']).to eq('Test User')
      end

      it 'sets authentication cookie' do
        post '/api/v1/auth/register', params: valid_attributes
        expect(response.cookies['auth_token']).to be_present
      end
    end

    context 'with invalid parameters' do
      it 'does not create a user with invalid email' do
        invalid_attributes = valid_attributes.deep_dup
        invalid_attributes[:user][:email] = 'invalid_email'
        
        expect {
          post '/api/v1/auth/register', params: invalid_attributes
        }.not_to change(User, :count)
      end

      it 'returns unprocessable entity status' do
        invalid_attributes = valid_attributes.deep_dup
        invalid_attributes[:user][:email] = ''
        
        post '/api/v1/auth/register', params: invalid_attributes
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'POST /api/v1/auth/login' do
    let!(:user) { create(:user, email: 'test@example.com', password: 'password123') }

    context 'with valid credentials' do
      it 'returns success' do
        post '/api/v1/auth/login', params: { email: 'test@example.com', password: 'password123' }
        expect(response).to have_http_status(:success)
      end

      it 'returns user data' do
        post '/api/v1/auth/login', params: { email: 'test@example.com', password: 'password123' }
        json = JSON.parse(response.body)
        
        expect(json['user']['email']).to eq('test@example.com')
      end

      it 'sets authentication cookie' do
        post '/api/v1/auth/login', params: { email: 'test@example.com', password: 'password123' }
        expect(response.cookies['auth_token']).to be_present
      end

      it 'is case insensitive for email' do
        post '/api/v1/auth/login', params: { email: 'TEST@EXAMPLE.COM', password: 'password123' }
        expect(response).to have_http_status(:success)
      end
    end

    context 'with invalid credentials' do
      it 'returns unauthorized with wrong password' do
        post '/api/v1/auth/login', params: { email: 'test@example.com', password: 'wrongpassword' }
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns unauthorized with non-existent email' do
        post '/api/v1/auth/login', params: { email: 'nonexistent@example.com', password: 'password123' }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'DELETE /api/v1/auth/logout' do
    let!(:user) { create(:user) }
    
    before do
      token = AuthenticationService.encode_token(user_id: user.id)
      cookies.signed[:auth_token] = token
    end

    it 'returns success' do
      delete '/api/v1/auth/logout'
      expect(response).to have_http_status(:success)
    end

    it 'clears the authentication cookie' do
      delete '/api/v1/auth/logout'
      expect(response.cookies['auth_token']).to be_nil
    end
  end

  describe 'GET /api/v1/auth/me' do
    let!(:user) { create(:user) }

    context 'with valid token' do
      before do
        token = AuthenticationService.encode_token(user_id: user.id)
        cookies.signed[:auth_token] = token
      end

      it 'returns current user data' do
        get '/api/v1/auth/me'
        expect(response).to have_http_status(:success)
        
        json = JSON.parse(response.body)
        expect(json['user']['id']).to eq(user.id)
        expect(json['user']['email']).to eq(user.email)
      end
    end

    context 'without token' do
      it 'returns unauthorized' do
        get '/api/v1/auth/me'
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/auth/refresh' do
    let!(:user) { create(:user) }

    context 'with valid token' do
      before do
        token = AuthenticationService.encode_token(user_id: user.id)
        cookies.signed[:auth_token] = token
      end

      it 'returns success' do
        post '/api/v1/auth/refresh'
        expect(response).to have_http_status(:success)
      end

      it 'sets a new authentication cookie' do
        old_token = cookies.signed[:auth_token]
        post '/api/v1/auth/refresh'
        new_token = response.cookies['auth_token']
        
        expect(new_token).to be_present
        expect(new_token).not_to eq(old_token)
      end
    end

    context 'without token' do
      it 'returns unauthorized' do
        post '/api/v1/auth/refresh'
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
