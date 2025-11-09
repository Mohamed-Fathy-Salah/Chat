class PaginationValidator
  include ActiveModel::Validations

  attr_accessor :page, :limit

  validates :page, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :limit, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100 }, allow_nil: true

  def initialize(params = {})
    @page = params[:page]
    @limit = params[:limit]
  end

  def page_value
    (page&.to_i || 1).clamp(1, Float::INFINITY).to_i
  end

  def limit_value
    (limit&.to_i || 10).clamp(1, 100)
  end
end
