Rails.application.routes.draw do
  get 'signup', to: 'users#new', as: 'signup'
  get 'login', to: 'sessions#new', as: 'login'
  get 'logout', to: 'sessions#destroy', as: 'logout'
  resources :users
  resources :sessions, only: [:new, :create, :destroy]

  root "blogs#index"
  resources :blogs, only: [:index, :create, :update, :destroy], param: :id
  get '/blogs/add', to: 'blogs#add'
  get '/blogs/:id', to: 'blogs#show'
  get '/blogs/:id/setup', to: 'blogs#setup'
  post '/blogs/:id/pause', to: 'blogs#pause'
  post '/blogs/:id/unpause', to: 'blogs#unpause'
  get '/blogs/:id/feed', to: 'rss#show'
  post 'discover_feeds', to: 'discover_feeds#discover'

  mount ActionCable.server => '/cable'
end
