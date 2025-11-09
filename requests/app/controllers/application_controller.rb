class ApplicationController < ActionController::API
  include ActionController::Cookies
  include Validatable

  before_action :authenticate_request

  attr_reader :current_user_id

  private

  def authenticate_request
    token = cookies.signed[:auth_token]
    return render_unauthorized unless token

    payload = AuthenticationService.decode_token(token)
    return render_unauthorized unless payload

    # Store only user_id, don't query database
    @current_user_id = payload['user_id']
    render_unauthorized unless @current_user_id
  rescue
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

    # Store only user_id, don't query database
    @current_user_id = payload['user_id']
  rescue
    @current_user_id = nil
  end
end
