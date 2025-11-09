module Api
  module V1
    class ChatsController < ApplicationController
      before_action :authorize_request

      # POST /api/v1/applications/:token/chats
      def create
        validator = validate_params(ChatParamsValidator, :create)
        return unless validator

        # Get next chat number using Redis (returns nil if app not found)
        chat_number = get_next_chat_number(validator.token)
        
        if chat_number.nil?
          return render json: { error: 'Application not found' }, status: :not_found
        end

        # Publish to RabbitMQ for async processing
        publish_chat_creation(validator.token, chat_number, current_user_id)
        
        render json: { chatNumber: chat_number }, status: :created
      end

      # GET /api/v1/applications/:token/chats
      def index
        validator = validate_params(ChatParamsValidator, :index)
        return unless validator

        page = validator.page_value
        limit = validator.limit_value
        offset = (page - 1) * limit

        chats = Chat.where(token: validator.token)
                    .select(:number, :messages_count)
                    .order(id: :desc)
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
            -- Atomically initialize from database value
            local count_str = ARGV[2]
            if count_str == 'nil' then
              return {-1, 'not_found'}
            end
            local count = tonumber(count_str)
            -- Use SET NX to avoid race condition
            if redis.call('SET', key, count, 'NX') then
              local new_count = redis.call('INCR', key)
              redis.call('SADD', 'chat_changes', token)
              return {new_count, 'initialized'}
            else
              -- Another request initialized it
              local new_count = redis.call('INCR', key)
              redis.call('SADD', 'chat_changes', token)
              return {new_count, 'concurrent'}
            end
          else
            -- Key exists, increment it
            local new_count = redis.call('INCR', key)
            redis.call('SADD', 'chat_changes', token)
            return {new_count, 'ok'}
          end
        LUA
        
        # Get current count from database
        count = Application.where(token: token).pick(:chats_count)
        return nil if count.nil?
        
        result = REDIS.eval(lua_script, keys: [key], argv: [token, count.to_s])
        result[0]
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
