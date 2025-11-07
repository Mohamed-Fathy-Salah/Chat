class AuthenticationService
  SECRET_KEY_PREFIX = 'auth_secret_key'
  KEY_ROTATION_INTERVAL = 2.days.to_i

  class << self
    def encode_token(payload)
      payload[:exp] = 7.days.from_now.to_i
      JWT.encode(payload, current_secret_key, 'HS256')
    end

    def decode_token(token)
      # Try current key first
      begin
        decoded = JWT.decode(token, current_secret_key, true, { algorithm: 'HS256' })
        return decoded[0]
      rescue JWT::DecodeError, JWT::ExpiredSignature
        # Try previous key for rotation grace period
        begin
          decoded = JWT.decode(token, previous_secret_key, true, { algorithm: 'HS256' })
          return decoded[0]
        rescue JWT::DecodeError, JWT::ExpiredSignature
          nil
        end
      end
    end

    def current_secret_key
      key = REDIS.get(current_key_name)
      
      if key.nil?
        key = generate_secret_key
        store_secret_key(key)
      end
      
      key
    end

    def previous_secret_key
      REDIS.get(previous_key_name) || current_secret_key
    end

    def rotate_secret_key!
      # Move current key to previous
      current_key = current_secret_key
      REDIS.set(previous_key_name, current_key, ex: KEY_ROTATION_INTERVAL)
      
      # Generate and store new key
      new_key = generate_secret_key
      store_secret_key(new_key)
      
      Rails.logger.info "Secret key rotated at #{Time.current}"
      new_key
    end

    private

    def generate_secret_key
      SecureRandom.hex(64)
    end

    def store_secret_key(key)
      REDIS.set(current_key_name, key, ex: KEY_ROTATION_INTERVAL * 2)
    end

    def current_key_name
      "#{SECRET_KEY_PREFIX}:current"
    end

    def previous_key_name
      "#{SECRET_KEY_PREFIX}:previous"
    end

    def key_rotation_timestamp
      REDIS.get("#{SECRET_KEY_PREFIX}:last_rotation")&.to_i || 0
    end

    def should_rotate?
      Time.current.to_i - key_rotation_timestamp > KEY_ROTATION_INTERVAL
    end
  end
end
