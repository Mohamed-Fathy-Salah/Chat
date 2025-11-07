class Chat < ApplicationRecord
  belongs_to :application
  belongs_to :creator, class_name: 'User'
  has_many :messages, dependent: :destroy

  validates :number, presence: true, uniqueness: { scope: :application_id }

  before_validation :set_token, on: :create

  private

  def set_token
    self.token = application.token if application
  end
end
