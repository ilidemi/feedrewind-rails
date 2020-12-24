Rails.application.routes.draw do
  root "blogs#index"
  resources :blogs, only: [:index, :new, :create, :destroy]
  get '/:name/feed', to: 'rss#show'
end
