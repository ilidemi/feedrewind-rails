Rails.application.routes.draw do
  root "landing#index"
  post "/discard", to: "landing#discard"

  get "signup", to: "users#new", as: "signup"
  post "signup", to: "users#create"
  get "login", to: "sessions#new", as: "login"
  post "login", to: "sessions#create"
  get "logout", to: "sessions#destroy", as: "logout"

  resources :subscriptions, only: [:index, :create, :update, :destroy], param: :id
  get "/subscriptions/add", to: "onboarding#add"
  post "/subscriptions/add", to: "onboarding#add_landing"
  post "/subscriptions/discover_feeds", to: "onboarding#discover_feeds"

  get "/subscriptions/:id", to: "subscriptions#show" # Should come after /add so that it doesn't get treated as id
  get "/subscriptions/:id/setup", to: "subscriptions#setup"

  # all js should be post for CSRF to work
  post "/subscriptions/:id/progress", to: "subscriptions#progress"
  post "/subscriptions/:id/submit_progress_times", to: "subscriptions#submit_progress_times"
  post "/subscriptions/:id/all_posts", to: "subscriptions#all_posts"
  post "/subscriptions/:id/confirm", to: "subscriptions#confirm"
  post "/subscriptions/:id/mark_wrong", to: "subscriptions#mark_wrong"
  post "/subscriptions/:id/continue_with_wrong", to: "subscriptions#continue_with_wrong"
  post "/subscriptions/:id/schedule", to: "subscriptions#schedule"
  post "/subscriptions/:id/pause", to: "subscriptions#pause"
  post "/subscriptions/:id/unpause", to: "subscriptions#unpause"
  get "/subscriptions/:id/feed", to: "rss#show"

  get "/blogs/:id/unsupported", to: "blogs#unsupported"

  get "/admin/add_blog", to: "admin#add_blog"
  post "/admin/post_blog", to: "admin#post_blog"

  mount ActionCable.server => "/cable"
end
