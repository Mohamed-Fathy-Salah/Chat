module Api
  module V1
    class ChatsController < ApplicationController
      before_action :authorize_request

      # POST /api/v1/applications/:token/chats
      def create
        # Just verify token exists
        unless Application.where(token: params[:token]).exists?
          return render json: { error: 'Application not found' }, status: :not_found
        end

        # Get next chat number using Redis
        chat_number = get_next_chat_number(params[:token])

        # Publish to RabbitMQ for async processing
        publish_chat_creation(params[:token], chat_number, current_user.id)
        
        render json: { chatNumber: chat_number }, status: :ok
      end

      # GET /api/v1/applications/:token/chats
      def index
        # Just verify token exists
        unless Application.where(token: params[:token]).exists?
          return render json: { error: 'Application not found' }, status: :not_found
        end

        chats = Chat.where(token: params[:token]).select(:number, :messages_count)

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
        
        unless REDIS.exists?(key)
          # Fetch current count from database and initialize Redis
          count = Application.where(token: token).pick(:chats_count) || 0
          REDIS.set(key, count)
        end
        
        # Atomically increment and get new value
        new_count = REDIS.incr(key)
        
        # Add to change tracking set
        REDIS.sadd('chat_changes', token)
        
        new_count
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
