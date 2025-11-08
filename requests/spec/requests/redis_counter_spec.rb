require 'rails_helper'

RSpec.describe 'Redis Counter Operations', type: :request do
  let(:user) { create(:user) }
  let(:auth_token) { AuthenticationService.generate_token(user.id) }
  let(:application) { create(:application, creator: user) }

  before do
    cookies.signed[:auth_token] = auth_token
    REDIS.flushdb
  end

  describe 'Chat counter' do
    it 'increments chat counter on chat creation' do
      expect(REDIS).to receive(:incr).with("chat_counter:#{application.token}").and_return(1)
      
      post "/api/v1/applications/#{application.token}/chats"
      expect(response).to have_http_status(:ok)
    end

    it 'assigns sequential chat numbers' do
      allow(REDIS).to receive(:incr).and_return(1, 2, 3)
      
      3.times { post "/api/v1/applications/#{application.token}/chats" }
      
      chats = Chat.where(application: application).order(:number)
      expect(chats.pluck(:number)).to eq([1, 2, 3])
    end

    it 'maintains separate counters per application' do
      app1 = create(:application, creator: user)
      app2 = create(:application, creator: user)
      
      expect(REDIS).to receive(:incr).with("chat_counter:#{app1.token}").and_return(1)
      expect(REDIS).to receive(:incr).with("chat_counter:#{app2.token}").and_return(1)
      
      post "/api/v1/applications/#{app1.token}/chats"
      post "/api/v1/applications/#{app2.token}/chats"
      
      expect(Chat.find_by(application: app1).number).to eq(1)
      expect(Chat.find_by(application: app2).number).to eq(1)
    end

    it 'handles Redis connection failures gracefully' do
      allow(REDIS).to receive(:incr).and_raise(Redis::CannotConnectError)
      
      expect {
        post "/api/v1/applications/#{application.token}/chats"
      }.to raise_error(Redis::CannotConnectError)
    end
  end

  describe 'Message counter' do
    let(:chat) { create(:chat, application: application, creator: user, number: 1) }

    it 'increments message counter on message creation' do
      expect(REDIS).to receive(:incr)
        .with("message_counter:#{application.token}:#{chat.number}")
        .and_return(1)
      
      post "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
           params: { body: 'Test message' }
      expect(response).to have_http_status(:ok)
    end

    it 'assigns sequential message numbers within chat' do
      allow(REDIS).to receive(:incr).and_return(1, 2, 3)
      
      3.times do
        post "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
             params: { body: 'Test message' }
      end
      
      messages = Message.where(chat: chat).order(:number)
      expect(messages.pluck(:number)).to eq([1, 2, 3])
    end

    it 'maintains separate counters per chat' do
      chat1 = create(:chat, application: application, creator: user, number: 1)
      chat2 = create(:chat, application: application, creator: user, number: 2)
      
      expect(REDIS).to receive(:incr)
        .with("message_counter:#{application.token}:#{chat1.number}")
        .and_return(1)
      expect(REDIS).to receive(:incr)
        .with("message_counter:#{application.token}:#{chat2.number}")
        .and_return(1)
      
      post "/api/v1/applications/#{application.token}/chats/#{chat1.number}/messages",
           params: { body: 'Message in chat 1' }
      post "/api/v1/applications/#{application.token}/chats/#{chat2.number}/messages",
           params: { body: 'Message in chat 2' }
      
      expect(Message.find_by(chat: chat1).number).to eq(1)
      expect(Message.find_by(chat: chat2).number).to eq(1)
    end

    it 'counter persists across requests' do
      REDIS.set("message_counter:#{application.token}:#{chat.number}", 5)
      
      expect(REDIS).to receive(:incr)
        .with("message_counter:#{application.token}:#{chat.number}")
        .and_call_original
      
      post "/api/v1/applications/#{application.token}/chats/#{chat.number}/messages",
           params: { body: 'Test message' }
      
      json = JSON.parse(response.body)
      expect(json['messageNumber']).to eq(6)
    end
  end

  describe 'Counter key format' do
    it 'uses correct format for chat counter' do
      expect(REDIS).to receive(:incr).with("chat_counter:#{application.token}")
      
      post "/api/v1/applications/#{application.token}/chats"
    end

    it 'uses correct format for message counter' do
      chat = create(:chat, application: application, creator: user, number: 42)
      
      expect(REDIS).to receive(:incr).with("message_counter:#{application.token}:42")
      
      post "/api/v1/applications/#{application.token}/chats/42/messages",
           params: { body: 'Test' }
    end
  end
end
