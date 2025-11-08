module Api
  module V1
    class MessagesController < ApplicationController
      before_action :authorize_request
      before_action :find_application_and_chat

      # POST /api/v1/applications/:token/chats/:chat_number/messages
      def create
        return render json: { error: 'Chat not found' }, status: :not_found unless @chat

        # Get next message number using Redis
        message_number = get_next_message_number(@application.token, @chat.number)

        # Publish to RabbitMQ for async processing
        publish_message_creation(@application.token, @chat.number, message_number, current_user.id, params[:body])
        
        render json: { messageNumber: message_number }, status: :ok
      end

      # PUT /api/v1/applications/:token/chats/:chat_number/messages
      def update
        return render json: { error: 'Chat not found' }, status: :not_found unless @chat

        message = @chat.messages.find_by(number: params[:messageNumber])

        if message.nil?
          render json: { error: 'Message not found' }, status: :not_found
        elsif message.creator_id != current_user.id
          render json: { error: 'You can only edit your own messages' }, status: :forbidden
        else
          # Publish to RabbitMQ for async processing
          publish_message_update(@application.token, @chat.number, params[:messageNumber], params[:body])
          
          head :ok
        end
      end

      # GET /api/v1/applications/:token/chats/:chat_number/messages
      def index
        return render json: { error: 'Chat not found' }, status: :not_found unless @chat

        page = params[:page]&.to_i || 1
        limit = params[:limit]&.to_i || 10
        offset = (page - 1) * limit

        messages = @chat.messages
                        .includes(:creator)
                        .select('messages.*, users.name as sender_name')
                        .joins(:creator)
                        .order(created_at: :desc)
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
        return render json: { error: 'Chat not found' }, status: :not_found unless @chat

        query = params[:q]
        messages = MessageSearchService.search(@chat, query)

        render json: messages.map { |msg|
          {
            messageNumber: msg.number,
            body: msg.body,
            createdAt: msg.created_at
          }
        }, status: :ok
      end

      private

      def find_application_and_chat
        # Any authenticated user can access any application/chat for viewing/creating messages
        @application = Application.find_by(token: params[:token])
        @chat = @application&.chats&.find_by(number: params[:chat_number])
      end

      def get_next_message_number(token, chat_number)
        # Atomically increment and get the next message number from Redis
        key = "message_counter:#{token}:#{chat_number}"
        
        unless REDIS.exists?(key)
          # Fetch current count from database and initialize Redis
          count = Chat.find_by(token: token,number: chat_number).pick(:messages_count) || 0
          REDIS.setnx(key, count)
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
          chatNumber: chat_number,
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
          chatNumber: chat_number,
          messageNumber: message_number,
          body: body
        }
        
        RabbitMqService.publish('update_messages', msg_data.to_json)
      end
    end
  end
end
