Rails.application.routes.draw do
  get 'signup', to: 'users#new', as: 'signup'
  get 'login', to: 'sessions#new', as: 'login'
  get 'logout', to: 'sessions#destroy', as: 'logout'
  resources :users
  resources :sessions, only: [:new, :create, :destroy]

  root "blogs#index"
  resources :blogs, only: [:index, :show, :new, :create, :update, :destroy], param: :id
  get '/blogs/:id/setup', to: 'blogs#setup'
  post '/blogs/:id/pause', to: 'blogs#pause'
  post '/blogs/:id/unpause', to: 'blogs#unpause'
  get '/blogs/:id/feed', to: 'rss#show'

  mount ActionCable.server => '/cable'
end
