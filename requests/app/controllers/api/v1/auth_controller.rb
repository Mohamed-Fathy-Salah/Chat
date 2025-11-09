module Api
  module V1
    class AuthController < ApplicationController
      skip_before_action :authenticate_request, only: [:register, :login]

      def register
        validator = validate_params(AuthParamsValidator, :register)
        return unless validator

        user = User.new(
          email: validator.email&.downcase,
          password: validator.password,
          password_confirmation: validator.password_confirmation,
          name: validator.name
        )
        
        if user.save
          token = AuthenticationService.encode_token(user_id: user.id)
          set_auth_cookie(token)
          
          render json: { 
            message: 'User created successfully',
            user: user_response(user)
          }, status: :created
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def login
        validator = validate_params(AuthParamsValidator, :login)
        return unless validator

        user = User.find_by(email: validator.email&.downcase)
        
        if user&.authenticate(validator.password)
          token = AuthenticationService.encode_token(user_id: user.id)
          set_auth_cookie(token)
          
          render json: { 
            message: 'Logged in successfully',
            user: user_response(user)
          }
        else
          render json: { error: 'Invalid email or password' }, status: :unauthorized
        end
      end

      def logout
        cookies.delete(:auth_token)
        render json: { message: 'Logged out successfully' }
      end

      def me
        user = User.find(current_user_id)
        render json: { user: user_response(user) }
      end

      def refresh
        # Generate new token with same user_id
        token = AuthenticationService.encode_token(user_id: current_user_id)
        set_auth_cookie(token)
        
        render json: { 
          message: 'Token refreshed successfully'
        }
      end

      private

      def user_params
        params.permit(:email, :password, :password_confirmation, :name)
      end

      def set_auth_cookie(token)
        cookies.signed[:auth_token] = {
          value: token,
          httponly: true,
          secure: Rails.env.production?,
          same_site: :lax,
          expires: 7.days.from_now
        }
      end

      def user_response(user)
        {
          id: user.id,
          email: user.email,
          name: user.name,
          created_at: user.created_at
        }
      end
    end
  end
end
