class MessageParamsValidator
  include ActiveModel::Validations

  attr_accessor :body, :token, :chat_number, :message_number, :query, :page, :limit

  validates :body, presence: true, length: { minimum: 1, maximum: 10000 }, on: [:create, :update]
  validates :token, presence: true, format: { with: /\A[a-zA-Z0-9_-]+\z/ }
  validates :chat_number, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :message_number, presence: true, numericality: { only_integer: true, greater_than: 0 }, on: :update
  validates :query, length: { maximum: 1000 }, allow_blank: true, on: :search
  validates :page, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true, on: [:index, :search]
  validates :limit, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100 }, allow_nil: true, on: [:index, :search]

  def initialize(params = {}, context = :create)
    @body = params[:body]
    @token = params[:token]
    @chat_number = params[:chat_number]
    @message_number = params[:messageNumber] || params[:message_number]
    @query = params[:q] || params[:query]
    @page = params[:page]
    @limit = params[:limit]
    @validation_context = context
  end

  def valid?
    super(@validation_context)
  end

  def page_value
    (@page&.to_i || 1).clamp(1, Float::INFINITY).to_i
  end

  def limit_value
    (@limit&.to_i || 10).clamp(1, 100)
  end
end
