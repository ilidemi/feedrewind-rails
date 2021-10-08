Rails.application.routes.draw do
  get 'signup', to: 'users#new', as: 'signup'
  get 'login', to: 'sessions#new', as: 'login'
  get 'logout', to: 'sessions#destroy', as: 'logout'
  resources :users
  resources :sessions, only: [:new, :create, :destroy]

  root "blogs#index"
  resources :blogs, only: [:index, :show, :new, :create, :update, :destroy], param: :name
  get '/:name/status', to: 'blogs#status'
  post '/:name/pause', to: 'blogs#pause'
  post '/:name/unpause', to: 'blogs#unpause'
  get '/:user_id/:name/feed', to: 'rss#show'

  mount ActionCable.server => '/cable'
end
