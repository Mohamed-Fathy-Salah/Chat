class AuthParamsValidator
  include ActiveModel::Validations

  attr_accessor :email, :password, :password_confirmation, :name

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: 255 }
  validates :password, presence: true, length: { minimum: 6, maximum: 128 }, on: [:register, :login]
  validates :password_confirmation, presence: true, on: :register
  validates :name, presence: true, length: { minimum: 1, maximum: 255 }, on: :register

  validate :passwords_match, on: :register

  def initialize(params = {}, context = :login)
    @email = params[:email]
    @password = params[:password]
    @password_confirmation = params[:password_confirmation]
    @name = params[:name]
    @validation_context = context
  end

  def valid?
    super(@validation_context)
  end

  private

  def passwords_match
    if password.present? && password_confirmation.present? && password != password_confirmation
      errors.add(:password_confirmation, "doesn't match password")
    end
  end
end
