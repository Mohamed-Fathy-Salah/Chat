class ApplicationController < ActionController::API
  include ActionController::Cookies
  include Validatable

  before_action :authenticate_request

  attr_reader :current_user

  private

  def authenticate_request
    token = cookies.signed[:auth_token]
    return render_unauthorized unless token

    payload = AuthenticationService.decode_token(token)
    return render_unauthorized unless payload

    @current_user = User.find_by(id: payload['user_id'])
    render_unauthorized unless @current_user
  rescue ActiveRecord::RecordNotFound
    render_unauthorized
  end

  def authorize_request
    authenticate_request
  end

  def render_unauthorized(message = 'Unauthorized')
    render json: { error: message }, status: :unauthorized
  end

  def authenticate_request_optional
    token = cookies.signed[:auth_token]
    return unless token

    payload = AuthenticationService.decode_token(token)
    return unless payload

    @current_user = User.find_by(id: payload['user_id'])
  rescue ActiveRecord::RecordNotFound
    @current_user = nil
  end
end
