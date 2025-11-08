module Api
  module V1
    class ChatsController < ApplicationController
      before_action :authorize_request
      before_action :find_application

      # POST /api/v1/applications/:token/chats
      def create
        return render json: { error: 'Application not found' }, status: :not_found unless @application

        # Get next chat number using Redis
        chat_number = get_next_chat_number(@application.token)

        # Publish to RabbitMQ for async processing
        publish_chat_creation(@application.token, chat_number, current_user.id)
        
        render json: { chatNumber: chat_number }, status: :ok
      end

      # GET /api/v1/applications/:token/chats
      def index
        return render json: { error: 'Application not found' }, status: :not_found unless @application

        chats = @application.chats.select(:number, :messages_count)

        render json: chats.map { |chat|
          {
            chatNumber: chat.number,
            messagesCount: chat.messages_count
          }
        }, status: :ok
      end

      private

      def find_application
        # Any authenticated user can access any application for viewing/creating chats
        @application = Application.find_by(token: params[:token])
      end

      def get_next_chat_number(token)
        # Atomically increment and get the next chat number from Redis
        key = "chat_counter:#{token}"
        count = REDIS.get(key)
        
        if count.nil?
          # Fetch current count from database and initialize Redis
          app = Application.find_by(token: token)
          count = app ? app.chats_count : 0
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
