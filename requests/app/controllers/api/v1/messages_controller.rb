module Api
  module V1
    class MessagesController < ApplicationController
      before_action :authorize_request

      # POST /api/v1/applications/:token/chats/:chat_number/messages
      def create
        validator = validate_params(MessageParamsValidator, :create)
        return unless validator

        # Get next message number using Redis (returns nil if chat not found)
        message_number = get_next_message_number(validator.token, validator.chat_number)
        
        if message_number.nil?
          return render json: { error: 'Chat not found' }, status: :not_found
        end

        # Publish to RabbitMQ for async processing
        publish_message_creation(validator.token, validator.chat_number, message_number, current_user_id, validator.body)
        
        render json: { messageNumber: message_number }, status: :ok
      end

      # PUT /api/v1/applications/:token/chats/:chat_number/messages
      def update
        validator = validate_params(MessageParamsValidator, :update)
        return unless validator

        message = Message.where(token: validator.token, chat_number: validator.chat_number, number: validator.message_number)
                         .pick(:creator_id)

        if message.nil?
          render json: { error: 'Message not found' }, status: :not_found
        elsif message != current_user.id
          render json: { error: 'You can only edit your own messages' }, status: :forbidden
        else
          # Publish to Elasticsearch for async indexing
          publish_message_update(validator.token, validator.chat_number, validator.message_number, validator.body)
          
          head :ok
        end
      end

      # GET /api/v1/applications/:token/chats/:chat_number/messages
      def index
        validator = validate_params(MessageParamsValidator, :index)
        return unless validator

        page = validator.page_value
        limit = validator.limit_value
        offset = (page - 1) * limit

        messages = Message.where(token: validator.token, chat_number: validator.chat_number)
                          .joins(:creator)
                          .select('messages.number, messages.body, messages.created_at, users.name as sender_name')
                          .order(id: :desc)
                          .limit(limit)
                          .offset(offset)

        render json: messages.map { |msg|
          {
            messageNumber: msg.number,
            senderName: msg.sender_name,
            body: msg.body,
            createdAt: msg.created_at
          }
        }, status: :ok
      end

      # GET /api/v1/applications/:token/chats/:chat_number/messages/search
      def search
        validator = validate_params(MessageParamsValidator, :search)
        return unless validator

        page = validator.page_value
        limit = validator.limit_value

        # Search directly in Elasticsearch - no need to check if chat exists
        # If chat doesn't exist, Elasticsearch will return empty results
        messages = MessageSearchService.search(validator.token, validator.chat_number, validator.query, page, limit)

        render json: messages.map { |msg|
          {
            messageNumber: msg.number,
            senderName: msg.sender_name,
            body: msg.body,
            createdAt: msg.created_at
          }
        }, status: :ok
      end

      private

      def get_next_message_number(token, chat_number)
        # Atomically increment and get the next message number from Redis
        key = "message_counter:#{token}:#{chat_number}"
        change_key = "#{token}:#{chat_number}"
        
        # Use Lua script for atomic initialization and increment
        lua_script = <<~LUA
          local key = KEYS[1]
          local change_key = ARGV[1]
          
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
              redis.call('SADD', 'message_changes', change_key)
              return {new_count, 'initialized'}
            else
              -- Another request initialized it
              local new_count = redis.call('INCR', key)
              redis.call('SADD', 'message_changes', change_key)
              return {new_count, 'concurrent'}
            end
          else
            -- Key exists, increment it
            local new_count = redis.call('INCR', key)
            redis.call('SADD', 'message_changes', change_key)
            return {new_count, 'ok'}
          end
        LUA
        
        # Get current count from database
        count = Chat.where(token: token, number: chat_number).pick(:messages_count)
        return nil if count.nil?
        
        result = REDIS.eval(lua_script, keys: [key], argv: [change_key, count.to_s])
        result[0]
      end

      def publish_message_creation(token, chat_number, message_number, sender_id, body)
        # Publish to RabbitMQ for async processing
        msg_data = {
          token: token,
          chatNumber: chat_number.to_i,
          messageNumber: message_number,
          senderId: sender_id,
          body: body,
          date: Time.now.utc.iso8601
        }
        
        RabbitMqService.publish('create_messages', msg_data.to_json)
      end

      def publish_message_update(token, chat_number, message_number, body)
        # Publish to RabbitMQ for async processing
        msg_data = {
          token: token,
          chatNumber: chat_number.to_i,
          messageNumber: message_number.to_i,
          body: body
        }
        
        RabbitMqService.publish('update_messages', msg_data.to_json)
      end
    end
  end
end
