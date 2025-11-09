module Validatable
  extend ActiveSupport::Concern

  private

  def validate_params(validator_class, context = :create)
    # PaginationValidator doesn't use context, others do
    validator = if validator_class == PaginationValidator
                  validator_class.new(params.to_unsafe_h.symbolize_keys)
                else
                  validator_class.new(params.to_unsafe_h.symbolize_keys, context)
                end
    
    unless validator.valid?
      render json: { errors: validator.errors.full_messages }, status: :unprocessable_entity
      return false
    end
    
    validator
  end

  def render_validation_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end
end
