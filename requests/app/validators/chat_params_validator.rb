class ChatParamsValidator
  include ActiveModel::Validations

  attr_accessor :token, :page, :limit

  validates :token, presence: true, format: { with: /\A[a-zA-Z0-9_-]+\z/ }
  validates :page, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true, on: :index
  validates :limit, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100 }, allow_nil: true, on: :index

  def initialize(params = {}, context = :create)
    @token = params[:token]
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
