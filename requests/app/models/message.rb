class Message < ApplicationRecord
  belongs_to :creator, class_name: 'User'

  validates :number, presence: true, uniqueness: { scope: [:token, :chat_number] }
  validates :body, presence: true
  validates :token, presence: true
  validates :chat_number, presence: true
end
