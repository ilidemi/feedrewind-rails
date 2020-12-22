Rails.application.routes.draw do
  root "blogs#index"

  resources :articles
  resources :blogs, only: [:index, :new, :create, :destroy]
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
end
