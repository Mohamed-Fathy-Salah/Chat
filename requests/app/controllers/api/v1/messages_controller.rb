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

        msg_data = {
          token: validator.token,
          chatNumber: validator.chat_number.to_i,
          messageNumber: message_number,
          senderId: current_user_id,
          body: validator.body,
          date: Time.now.utc.iso8601
        }
        
        RabbitMqService.publish('create_messages', msg_data.to_json)
        
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
        elsif message != current_user_id
          render json: { error: 'You can only edit your own messages' }, status: :forbidden
        else 
          msg_data = {
            token: validator.token,
            chatNumber: validator.chat_number.to_i,
            messageNumber: validator.message_number.to_i,
            body: validator.body
          }
          RabbitMqService.publish('update_messages', msg_data.to_json)
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
        key = "message_counter:#{token}:#{chat_number}"
        change_key = "#{token}:#{chat_number}"
        
        incremented_number = REDIS.increment_if_exists(key)
        
        if incremented_number.nil?
          count = Chat.where(token: token, number: chat_number).pick(:messages_count)
          return nil if count.nil?
          
          incremented_number = REDIS.increment_with_default_value(key, count)
        end
        
        REDIS.sadd('message_changes', change_key)
        incremented_number
      end
    end
  end
end
