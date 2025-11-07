Rails.application.routes.draw do
  # Swagger UI routes (development only)
  if Rails.env.development?
    mount Rswag::Ui::Engine => '/api-docs'
    mount Rswag::Api::Engine => '/api-docs'
  end

  namespace :api do
    namespace :v1 do
      # Auth routes
      post 'auth/register', to: 'auth#register'
      post 'auth/login', to: 'auth#login'
      delete 'auth/logout', to: 'auth#logout'
      get 'auth/me', to: 'auth#me'
      post 'auth/refresh', to: 'auth#refresh'

      # Application routes
      post 'applications', to: 'applications#create'
      put 'applications', to: 'applications#update'
      get 'applications', to: 'applications#index'

      # Chat routes
      post 'applications/:token/chats', to: 'chats#create'
      get 'applications/:token/chats', to: 'chats#index'

      # Message routes
      post 'applications/:token/chats/:chat_number/messages', to: 'messages#create'
      put 'applications/:token/chats/:chat_number/messages', to: 'messages#update'
      get 'applications/:token/chats/:chat_number/messages', to: 'messages#index'
      get 'applications/:token/chats/:chat_number/messages/search', to: 'messages#search'
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
