module Api
  module V1
    class MessagesController < ApplicationController
      before_action :authorize_request

      # POST /api/v1/applications/:token/chats/:chat_number/messages
      def create
        # Just verify chat exists
        unless Chat.where(token: params[:token], number: params[:chat_number]).exists?
          return render json: { error: 'Chat not found' }, status: :not_found
        end

        # Get next message number using Redis
        message_number = get_next_message_number(params[:token], params[:chat_number])

        # Publish to RabbitMQ for async processing
        publish_message_creation(params[:token], params[:chat_number], message_number, current_user.id, params[:body])
        
        render json: { messageNumber: message_number }, status: :ok
      end

      # PUT /api/v1/applications/:token/chats/:chat_number/messages
      def update
        message = Message.where(token: params[:token], chat_number: params[:chat_number], number: params[:messageNumber])
                         .pick(:creator_id)

        if message.nil?
          render json: { error: 'Message not found' }, status: :not_found
        elsif message != current_user.id
          render json: { error: 'You can only edit your own messages' }, status: :forbidden
        else
          # Publish to RabbitMQ for async processing
          publish_message_update(params[:token], params[:chat_number], params[:messageNumber], params[:body])
          
          head :ok
        end
      end

      # GET /api/v1/applications/:token/chats/:chat_number/messages
      def index
        # Just verify chat exists
        unless Chat.where(token: params[:token], number: params[:chat_number]).exists?
          return render json: { error: 'Chat not found' }, status: :not_found
        end

        page = params[:page]&.to_i || 1
        limit = params[:limit]&.to_i || 10
        offset = (page - 1) * limit

        messages = Message.where(token: params[:token], chat_number: params[:chat_number])
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
        # Just verify chat exists
        unless Chat.where(token: params[:token], number: params[:chat_number]).exists?
          return render json: { error: 'Chat not found' }, status: :not_found
        end

        query = params[:q]
        messages = MessageSearchService.search(params[:token], params[:chat_number], query)

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
        
        unless REDIS.exists?(key)
          # Fetch current count from database and initialize Redis
          count = Chat.where(token: token, number: chat_number).pick(:messages_count) || 0
          REDIS.set(key, count)
        end
        
        # Atomically increment and get new value
        new_count = REDIS.incr(key)
        
        # Add to change tracking set
        REDIS.sadd('message_changes', "#{token}:#{chat_number}")
        
        new_count
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
