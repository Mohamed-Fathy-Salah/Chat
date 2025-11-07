require 'rails_helper'

RSpec.describe AuthenticationService do
  describe '.encode_token' do
    it 'creates a JWT token with expiration' do
      payload = { user_id: 1 }
      token = AuthenticationService.encode_token(payload)
      
      expect(token).to be_a(String)
      expect(token.split('.').length).to eq(3) # JWT has 3 parts
    end
  end

  describe '.decode_token' do
    it 'decodes a valid token' do
      payload = { user_id: 1 }
      token = AuthenticationService.encode_token(payload)
      decoded = AuthenticationService.decode_token(token)
      
      expect(decoded['user_id']).to eq(1)
      expect(decoded['exp']).to be > Time.current.to_i
    end

    it 'returns nil for invalid token' do
      decoded = AuthenticationService.decode_token('invalid_token')
      expect(decoded).to be_nil
    end

    it 'returns nil for expired token' do
      payload = { user_id: 1, exp: 1.hour.ago.to_i }
      token = JWT.encode(payload, AuthenticationService.current_secret_key, 'HS256')
      decoded = AuthenticationService.decode_token(token)
      
      expect(decoded).to be_nil
    end
  end

  describe '.current_secret_key' do
    it 'generates a secret key if none exists' do
      REDIS.flushdb
      key = AuthenticationService.current_secret_key
      
      expect(key).to be_a(String)
      expect(key.length).to eq(128) # 64 bytes in hex = 128 characters
    end

    it 'returns the same key on subsequent calls' do
      REDIS.flushdb
      key1 = AuthenticationService.current_secret_key
      key2 = AuthenticationService.current_secret_key
      
      expect(key1).to eq(key2)
    end
  end

  describe '.rotate_secret_key!' do
    it 'generates a new secret key' do
      REDIS.flushdb
      old_key = AuthenticationService.current_secret_key
      AuthenticationService.rotate_secret_key!
      new_key = AuthenticationService.current_secret_key
      
      expect(new_key).not_to eq(old_key)
    end

    it 'keeps the old key as previous key' do
      REDIS.flushdb
      old_key = AuthenticationService.current_secret_key
      AuthenticationService.rotate_secret_key!
      previous_key = AuthenticationService.previous_secret_key
      
      expect(previous_key).to eq(old_key)
    end

    it 'allows decoding tokens signed with previous key' do
      REDIS.flushdb
      payload = { user_id: 1 }
      token = AuthenticationService.encode_token(payload)
      
      AuthenticationService.rotate_secret_key!
      
      decoded = AuthenticationService.decode_token(token)
      expect(decoded['user_id']).to eq(1)
    end
  end
end
