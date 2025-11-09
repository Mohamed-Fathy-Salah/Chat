module Api
  module V1
    class MessagesController < ApplicationController
      before_action :authorize_request

      # POST /api/v1/applications/:token/chats/:chat_number/messages
      def create
        validator = validate_params(MessageParamsValidator, :create)
        return unless validator

        # Just verify chat exists
        unless Chat.where(token: validator.token, number: validator.chat_number).exists?
          return render json: { error: 'Chat not found' }, status: :not_found
        end

        # Get next message number using Redis
        message_number = get_next_message_number(validator.token, validator.chat_number)

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

        # Just verify chat exists
        unless Chat.where(token: validator.token, number: validator.chat_number).exists?
          return render json: { error: 'Chat not found' }, status: :not_found
        end

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
            -- Key doesn't exist, we need to initialize it
            return -1
          else
            -- Key exists, increment it
            local new_count = redis.call('INCR', key)
            redis.call('SADD', 'message_changes', change_key)
            return new_count
          end
        LUA
        
        result = REDIS.eval(lua_script, keys: [key], argv: [change_key])
        
        if result == -1
          # Initialize counter from database (race condition handled by SET NX)
          count = Chat.where(token: token, number: chat_number).pick(:messages_count) || 0
          
          # SET NX: only sets if key doesn't exist (atomic)
          if REDIS.set(key, count, nx: true)
            # We successfully initialized, now increment
            new_count = REDIS.incr(key)
            REDIS.sadd('message_changes', change_key)
            new_count
          else
            # Another request initialized it, just increment
            new_count = REDIS.incr(key)
            REDIS.sadd('message_changes', change_key)
            new_count
          end
        else
          result
        end
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
