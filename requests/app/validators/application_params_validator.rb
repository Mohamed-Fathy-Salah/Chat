class ApplicationParamsValidator
  include ActiveModel::Validations

  attr_accessor :name, :token

  validates :name, presence: true, length: { minimum: 1, maximum: 255 }, on: :create
  validates :name, length: { minimum: 1, maximum: 255 }, allow_nil: true, on: :update
  validates :token, presence: true, format: { with: /\A[a-zA-Z0-9_-]+\z/ }, on: :update

  def initialize(params = {}, context = :create)
    @name = params[:name]
    @token = params[:token]
    @validation_context = context
  end

  def valid?
    super(@validation_context)
  end
end
