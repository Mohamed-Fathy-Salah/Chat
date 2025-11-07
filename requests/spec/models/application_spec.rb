require 'rails_helper'

RSpec.describe Application, type: :model do
  describe 'associations' do
    it { should belong_to(:creator).class_name('User') }
    it { should have_many(:chats).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:token) }
    it { should validate_uniqueness_of(:token) }
  end

  describe 'callbacks' do
    it 'generates a token before validation on create' do
      user = User.create!(name: 'Test User', email: 'test@example.com', password: 'password123')
      application = Application.new(name: 'Test App', creator: user)
      
      expect(application.token).to be_nil
      application.valid?
      expect(application.token).not_to be_nil
    end
  end
end
