require 'rails_helper'

RSpec.describe 'Model Edge Cases', type: :model do
  let(:user) { create(:user) }

  describe Application do
    it 'generates unique tokens' do
      app1 = create(:application, creator: user)
      app2 = create(:application, creator: user)
      
      expect(app1.token).not_to eq(app2.token)
    end

    it 'token persists after update' do
      app = create(:application, creator: user)
      original_token = app.token
      
      app.update!(name: 'New Name')
      
      expect(app.reload.token).to eq(original_token)
    end

    it 'destroys dependent chats on deletion' do
      app = create(:application, creator: user)
      chat = create(:chat, application: app, creator: user)
      
      expect { app.destroy }.to change { Chat.count }.by(-1)
    end

    it 'chats_count defaults to 0' do
      app = create(:application, creator: user)
      expect(app.chats_count).to eq(0)
    end

    it 'validates token uniqueness' do
      app1 = create(:application, creator: user)
      app2 = build(:application, creator: user, token: app1.token)
      
      expect(app2).not_to be_valid
      expect(app2.errors[:token]).to include('has already been taken')
    end

    it 'token is readonly after creation' do
      app = create(:application, creator: user)
      original_token = app.token
      
      app.update(token: 'new_token')
      
      expect(app.reload.token).to eq(original_token)
    end
  end

  describe Chat do
    let(:application) { create(:application, creator: user) }

    it 'copies token from application' do
      chat = create(:chat, application: application, creator: user, number: 1)
      expect(chat.token).to eq(application.token)
    end

    it 'enforces uniqueness of number within application' do
      create(:chat, application: application, creator: user, number: 1)
      chat2 = build(:chat, application: application, creator: user, number: 1)
      
      expect(chat2).not_to be_valid
    end

    it 'allows same number in different applications' do
      app1 = create(:application, creator: user)
      app2 = create(:application, creator: user)
      
      chat1 = create(:chat, application: app1, creator: user, number: 1)
      chat2 = create(:chat, application: app2, creator: user, number: 1)
      
      expect(chat1.number).to eq(chat2.number)
    end

    it 'destroys dependent messages on deletion' do
      chat = create(:chat, application: application, creator: user)
      create(:message, chat: chat, creator: user, number: 1)
      
      expect { chat.destroy }.to change { Message.count }.by(-1)
    end

    it 'messages_count defaults to 0' do
      chat = create(:chat, application: application, creator: user)
      expect(chat.messages_count).to eq(0)
    end

    it 'requires number to be present' do
      chat = build(:chat, application: application, creator: user, number: nil)
      expect(chat).not_to be_valid
    end

    it 'number can be zero' do
      chat = build(:chat, application: application, creator: user, number: 0)
      expect(chat).to be_valid
    end
  end

  describe Message do
    let(:application) { create(:application, creator: user) }
    let(:chat) { create(:chat, application: application, creator: user, number: 1) }

    it 'copies token and chat_number from chat' do
      message = create(:message, chat: chat, creator: user, number: 1, body: 'Test')
      
      expect(message.token).to eq(chat.token)
      expect(message.chat_number).to eq(chat.number)
    end

    it 'enforces uniqueness of number within chat' do
      create(:message, chat: chat, creator: user, number: 1, body: 'First')
      message2 = build(:message, chat: chat, creator: user, number: 1, body: 'Second')
      
      expect(message2).not_to be_valid
    end

    it 'allows same number in different chats' do
      chat1 = create(:chat, application: application, creator: user, number: 1)
      chat2 = create(:chat, application: application, creator: user, number: 2)
      
      msg1 = create(:message, chat: chat1, creator: user, number: 1, body: 'Test 1')
      msg2 = create(:message, chat: chat2, creator: user, number: 1, body: 'Test 2')
      
      expect(msg1.number).to eq(msg2.number)
    end

    it 'requires body to be present' do
      message = build(:message, chat: chat, creator: user, number: 1, body: nil)
      expect(message).not_to be_valid
      expect(message.errors[:body]).to include("can't be blank")
    end

    it 'requires number to be present' do
      message = build(:message, chat: chat, creator: user, number: nil, body: 'Test')
      expect(message).not_to be_valid
    end

    it 'allows empty string body after validation removed' do
      message = build(:message, chat: chat, creator: user, number: 1, body: '')
      expect(message).not_to be_valid
    end

    it 'handles long message bodies' do
      long_body = 'a' * 10000
      message = create(:message, chat: chat, creator: user, number: 1, body: long_body)
      
      expect(message.body.length).to eq(10000)
    end

    it 'handles special characters in body' do
      special_body = "Test with émojis 🎉 and symbols @#$%"
      message = create(:message, chat: chat, creator: user, number: 1, body: special_body)
      
      expect(message.reload.body).to eq(special_body)
    end

    it 'updates updated_at timestamp' do
      message = create(:message, chat: chat, creator: user, number: 1, body: 'Original')
      original_time = message.updated_at
      
      sleep 0.1
      message.update!(body: 'Updated')
      
      expect(message.updated_at).to be > original_time
    end
  end

  describe User do
    it 'validates email uniqueness' do
      create(:user, email: 'test@example.com')
      user2 = build(:user, email: 'test@example.com')
      
      expect(user2).not_to be_valid
    end

    it 'validates email format' do
      user = build(:user, email: 'invalid-email')
      expect(user).not_to be_valid
    end

    it 'encrypts password' do
      user = create(:user, password: 'secret123')
      expect(user.password_digest).not_to eq('secret123')
      expect(user.password_digest).to be_present
    end

    it 'authenticates with correct password' do
      user = create(:user, password: 'secret123')
      expect(user.authenticate('secret123')).to eq(user)
    end

    it 'does not authenticate with wrong password' do
      user = create(:user, password: 'secret123')
      expect(user.authenticate('wrong')).to be false
    end

    it 'requires password on creation' do
      user = build(:user, password: nil)
      expect(user).not_to be_valid
    end

    it 'destroys dependent applications on deletion' do
      user = create(:user)
      create(:application, creator: user)
      
      expect { user.destroy }.to change { Application.count }.by(-1)
    end

    it 'destroys dependent chats on deletion' do
      user = create(:user)
      app = create(:application, creator: user)
      create(:chat, application: app, creator: user)
      
      expect { user.destroy }.to change { Chat.count }.by(-1)
    end

    it 'destroys dependent messages on deletion' do
      user = create(:user)
      app = create(:application, creator: user)
      chat = create(:chat, application: app, creator: user)
      create(:message, chat: chat, creator: user, number: 1)
      
      expect { user.destroy }.to change { Message.count }.by(-1)
    end
  end
end
