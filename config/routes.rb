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
  get "/subscriptions/add/*start_url", to: "onboarding#add", format: false, defaults: { format: "html" }
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

  get "/subscriptions/:id/feed", to: "rss#subscription_feed" # Legacy
  get "/feeds/single/:id", to: "rss#user_feed"
  get "/feeds/:id", to: "rss#subscription_feed"

  get "/blogs/:id/unsupported", to: "blogs#unsupported"

  get "/terms", to: "misc#terms"
  get "/privacy", to: "misc#privacy"
  get "/about", to: "misc#about"

  get "/admin/add_blog", to: "admin#add_blog"
  post "/admin/post_blog", to: "admin#post_blog"

  if Rails.env.development? || Rails.env.test?
    get "/test/travel_31days", to: "admin_test#travel_31days"
    get "/test/travel_back", to: "admin_test#travel_back"
    get "/test/reschedule_update_rss_job", to: "admin_test#reschedule_update_rss_job"
    get "/test/run_reset_failed_blogs_job", to: "admin_test#run_reset_failed_blogs_job"
    get "/test/destroy_user", to: "admin_test#destroy_user"
    get "/test/destroy_user_subscriptions", to: "admin_test#destroy_user_subscriptions"
    get "/test/user_timezone", to: "admin_test#user_timezone"
    get "/test/travel_to_v2", to: "admin_test#travel_to_v2"
    get "/test/travel_back_v2", to: "admin_test#travel_back_v2"
    get "/test/wait_for_update_rss_job", to: "admin_test#wait_for_update_rss_job"
    get "/test/execute_sql", to: "admin_test#execute_sql"
  end

  mount ActionCable.server => "/cable"
end
