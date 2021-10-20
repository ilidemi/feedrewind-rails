Rails.application.routes.draw do
  get 'onboarding/add'
  get 'onboarding/add_landing'
  root "landing#index"

  get 'signup', to: 'users#new', as: 'signup'
  get 'login', to: 'sessions#new', as: 'login'
  get 'logout', to: 'sessions#destroy', as: 'logout'
  resources :users
  resources :sessions, only: [:new, :create, :destroy]

  resources :blogs, only: [:index, :create, :update, :destroy], param: :id
  get '/blogs/add', to: 'onboarding#add'
  post '/blogs/add', to: 'onboarding#add_landing'
  post '/blogs/discover_feeds', to: 'onboarding#discover_feeds'

  get '/blogs/:id', to: 'blogs#show' # Should come after /add so that it doesn't get treated as id
  get '/blogs/:id/setup', to: 'blogs#setup'
  post '/blogs/:id/confirm', to: 'blogs#confirm'
  post '/blogs/:id/schedule', to: 'blogs#schedule'
  post '/blogs/:id/pause', to: 'blogs#pause'
  post '/blogs/:id/unpause', to: 'blogs#unpause'
  get '/blogs/:id/feed', to: 'rss#show'

  mount ActionCable.server => '/cable'
end
