Rails.application.routes.draw do
  root "blogs#index"
  resources :blogs, only: [:index, :show, :new, :create, :update, :destroy], param: :name
  get '/:name/status', to: 'blogs#status'
  post '/:name/pause', to: 'blogs#pause'
  post '/:name/unpause', to: 'blogs#unpause'
  get '/:name/feed', to: 'rss#show'
end
