class Chat < ApplicationRecord
  belongs_to :creator, class_name: 'User'

  validates :number, presence: true, uniqueness: { scope: :token }
  validates :token, presence: true
end
