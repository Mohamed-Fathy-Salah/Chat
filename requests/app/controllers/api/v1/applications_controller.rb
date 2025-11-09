module Api
  module V1
    class ApplicationsController < ApplicationController
      before_action :authorize_request

      # POST /api/v1/applications
      def create
        validator = validate_params(ApplicationParamsValidator, :create)
        return unless validator

        application = current_user.applications.new(name: validator.name)

        if application.save
          render json: { token: application.token }, status: :created
        else
          render json: { errors: application.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PUT /api/v1/applications
      def update
        validator = validate_params(ApplicationParamsValidator, :update)
        return unless validator

        # Only allow users to update their own applications
        application = current_user.applications.find_by(token: validator.token)

        if application.nil?
          render json: { error: 'Application not found or you do not have permission to edit it' }, status: :forbidden
        elsif application.update(name: validator.name)
          head :ok
        else
          render json: { errors: application.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/applications
      def index
        validator = validate_params(PaginationValidator, :index)
        return unless validator

        # Show all applications, not just user's own
        page = validator.page_value
        limit = validator.limit_value
        offset = (page - 1) * limit

        applications = Application.select(:token, :name, :chats_count)
                                  .limit(limit)
                                  .offset(offset)

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
