class AuthenticationService
  class << self
    def encode_token(payload)
      payload[:exp] = 7.days.from_now.to_i
      JWT.encode(payload, secret_key, 'HS256')
    end

    def decode_token(token)
      decoded = JWT.decode(token, secret_key, true, { algorithm: 'HS256' })
      decoded[0]
    rescue JWT::DecodeError, JWT::ExpiredSignature => e
      Rails.logger.warn "JWT decode failed: #{e.message}"
      nil
    end

    def generate_token(user_id:)
      encode_token(user_id: user_id)
    end

    private

    def secret_key
      key = ENV['JWT_SECRET_KEY']
      
      if key.nil? || key.empty?
        raise_missing_key_error
      end
      
      if key.length < 32
        Rails.logger.warn "JWT_SECRET_KEY is too short. Should be at least 32 characters."
      end
      
      key
    end

    def raise_missing_key_error
      error_message = <<~ERROR
        JWT_SECRET_KEY environment variable is not set!
        
        To generate a secure key, run:
          rails secret
        
        Or use:
          openssl rand -hex 64
        
        Then set it in your environment:
          export JWT_SECRET_KEY='your_generated_key'
        
        For production, set it in your deployment environment.
      ERROR
      
      raise ArgumentError, error_message
    end
  end
end
