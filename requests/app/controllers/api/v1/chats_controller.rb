module Api
  module V1
    class ChatsController < ApplicationController
      before_action :authorize_request

      # POST /api/v1/applications/:token/chats
      def create
        validator = validate_params(ChatParamsValidator, :create)
        return unless validator

        # Just verify token exists
        unless Application.where(token: validator.token).exists?
          return render json: { error: 'Application not found' }, status: :not_found
        end

        # Get next chat number using Redis
        chat_number = get_next_chat_number(validator.token)

        # Publish to RabbitMQ for async processing
        publish_chat_creation(validator.token, chat_number, current_user.id)
        
        render json: { chatNumber: chat_number }, status: :created
      end

      # GET /api/v1/applications/:token/chats
      def index
        validator = validate_params(ChatParamsValidator, :index)
        return unless validator

        # Just verify token exists
        unless Application.where(token: validator.token).exists?
          return render json: { error: 'Application not found' }, status: :not_found
        end

        page = validator.page_value
        limit = validator.limit_value
        offset = (page - 1) * limit

        chats = Chat.where(token: validator.token)
                    .select(:number, :messages_count)
                    .limit(limit)
                    .offset(offset)

        render json: chats.map { |chat|
          {
            chatNumber: chat.number,
            messagesCount: chat.messages_count
          }
        }, status: :ok
      end

      private

      def get_next_chat_number(token)
        # Atomically increment and get the next chat number from Redis
        key = "chat_counter:#{token}"
        
        # Use Lua script for atomic initialization and increment
        lua_script = <<~LUA
          local key = KEYS[1]
          local token = ARGV[1]
          
          if redis.call('EXISTS', key) == 0 then
            -- Key doesn't exist, we need to initialize it
            return -1
          else
            -- Key exists, increment it
            local new_count = redis.call('INCR', key)
            redis.call('SADD', 'chat_changes', token)
            return new_count
          end
        LUA
        
        result = REDIS.eval(lua_script, keys: [key], argv: [token])
        
        if result == -1
          # Initialize counter from database (race condition handled by SET NX)
          count = Application.where(token: token).pick(:chats_count) || 0
          
          # SET NX: only sets if key doesn't exist (atomic)
          if REDIS.set(key, count, nx: true)
            # We successfully initialized, now increment
            new_count = REDIS.incr(key)
            REDIS.sadd('chat_changes', token)
            new_count
          else
            # Another request initialized it, just increment
            new_count = REDIS.incr(key)
            REDIS.sadd('chat_changes', token)
            new_count
          end
        else
          result
        end
      end

      def publish_chat_creation(token, chat_number, creator_id)
        # Publish to RabbitMQ for async processing
        message = {
          token: token,
          chatNumber: chat_number,
          creatorId: creator_id
        }
        
        RabbitMqService.publish('create_chats', message.to_json)
      end
    end
  end
end
