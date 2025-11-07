module Api
  module V1
    class ApplicationsController < ApplicationController
      before_action :authorize_request

      # POST /api/v1/applications
      def create
        application = current_user.applications.new(name: params[:name])

        if application.save
          render json: { token: application.token }, status: :ok
        else
          render json: { errors: application.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PUT /api/v1/applications
      def update
        # Only allow users to update their own applications
        application = current_user.applications.find_by(token: params[:token])

        if application.nil?
          render json: { error: 'Application not found or you do not have permission to edit it' }, status: :forbidden
        elsif application.update(name: params[:name])
          head :ok
        else
          render json: { errors: application.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/applications
      def index
        # Show all applications, not just user's own
        applications = Application.select(:token, :name, :chats_count)

        render json: applications.map { |app|
          {
            token: app.token,
            name: app.name,
            chatsCount: app.chats_count
          }
        }, status: :ok
      end
    end
  end
end
