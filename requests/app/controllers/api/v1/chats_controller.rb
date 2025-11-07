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

        chat = @application.chats.new(
          number: chat_number,
          creator: current_user
        )

        if chat.save
          # Publish to RabbitMQ for async processing
          publish_chat_creation(chat)
          
          render json: { chatNumber: chat.number }, status: :ok
        else
          render json: { errors: chat.errors.full_messages }, status: :unprocessable_entity
        end
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
        # Increment and get the next chat number from Redis
        REDIS.incr("chat_counter:#{token}")
      end

      def publish_chat_creation(chat)
        # Publish to RabbitMQ for async processing
        message = {
          token: chat.token,
          chatNumber: chat.number,
          creatorId: chat.creator_id
        }
        
        RabbitMqService.publish('create_chats', message.to_json)
      end
    end
  end
end
