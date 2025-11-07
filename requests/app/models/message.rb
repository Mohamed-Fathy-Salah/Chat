class Message < ApplicationRecord
  belongs_to :chat
  belongs_to :creator, class_name: 'User'

  validates :number, presence: true, uniqueness: { scope: :chat_id }
  validates :body, presence: true

  before_validation :set_token_and_chat_number, on: :create

  private

  def set_token_and_chat_number
    if chat
      self.token = chat.token
      self.chat_number = chat.number
    end
  end
end
