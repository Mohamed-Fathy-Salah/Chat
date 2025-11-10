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

        message = {
          token: validator.token,
          chatNumber: chat_number,
          creatorId: current_user_id
        }
        
        RabbitMqService.publish('create_chats', message.to_json)
        
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
        key = "chat_counter:#{token}"
        
        incremented_number = REDIS.increment_if_exists(key)
        
        if incremented_number.nil?
          count = Application.where(token: token).pick(:chats_count)
          return nil if count.nil?
          
          incremented_number = REDIS.increment_with_default_value(key, count)
        end
        
        REDIS.sadd('chat_changes', token)
        incremented_number
      end
    end
  end
end
