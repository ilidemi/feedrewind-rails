Rails.application.routes.draw do
  root "landing#index"
  post "/discard", to: "landing#discard"

  get "signup", to: "users#new", as: "signup"
  post "signup", to: "users#create"
  get "login", to: "sessions#new", as: "login"
  post "login", to: "sessions#create"
  get "logout", to: "sessions#destroy", as: "logout"

  get "settings", to: "users#settings"
  post "settings/save_timezone", to: "users#save_timezone"
  post "settings/save_delivery_channel", to: "users#save_delivery_channel"

  resources :subscriptions, only: [:index, :create]
  get "/subscriptions/add", to: "onboarding#add"
  get "/subscriptions/add/*start_url", to: "onboarding#add", format: false, defaults: { format: "html" }
  post "/subscriptions/add", to: "onboarding#add_landing"
  post "/subscriptions/discover_feeds", to: "onboarding#discover_feeds"

  get "/subscriptions/:id", to: "subscriptions#show", constraints: { id: /\d+/ } # Should come after /add so that it doesn't get treated as id
  get "/subscriptions/:id/setup", to: "subscriptions#setup", constraints: { id: /\d+/ }

  # all js should be post for CSRF to work
  post "/subscriptions/:id/progress", to: "subscriptions#progress", constraints: { id: /\d+/ }
  post "/subscriptions/:id/submit_progress_times", to: "subscriptions#submit_progress_times", constraints: { id: /\d+/ }
  post "/subscriptions/:id/select_posts", to: "subscriptions#select_posts", constraints: { id: /\d+/ }
  post "/subscriptions/:id/mark_wrong", to: "subscriptions#mark_wrong", constraints: { id: /\d+/ }
  post "/subscriptions/:id/schedule", to: "subscriptions#schedule", constraints: { id: /\d+/ }
  post "/subscriptions/:id/pause", to: "subscriptions#pause", constraints: { id: /\d+/ }
  post "/subscriptions/:id/unpause", to: "subscriptions#unpause", constraints: { id: /\d+/ }
  post "/subscriptions/:id/delete", to: "subscriptions#delete", constraints: { id: /\d+/ }
  post "/subscriptions/:id", to: "subscriptions#update", constraints: { id: /\d+/ }

  get "/subscriptions/:id/feed", to: "rss#subscription_feed", constraints: { id: /\d+/ } # Legacy
  get "/feeds/single/:id", to: "rss#user_feed", constraints: { id: /\d+/ }
  get "/feeds/:id", to: "rss#subscription_feed", constraints: { id: /\d+/ }

  get "/blogs/:id/unsupported", to: "blogs#unsupported", constraints: { id: /\d+/ }

  get "/terms", to: "misc#terms"
  get "/privacy", to: "misc#privacy"
  get "/about", to: "misc#about"

  post "/postmark/report_bounce", to: "postmark#report_bounce"

  get "/admin/add_blog", to: "admin#add_blog"
  post "/admin/post_blog", to: "admin#post_blog"
  get "/admin/dashboard", to: "admin#dashboard"

  if Rails.env.development? || Rails.env.test?
    get "/test/travel_31days", to: "admin_test#travel_31days"
    get "/test/travel_back", to: "admin_test#travel_back"
    get "/test/reschedule_user_job", to: "admin_test#reschedule_user_job"
    get "/test/run_reset_failed_blogs_job", to: "admin_test#run_reset_failed_blogs_job"
    get "/test/destroy_user", to: "admin_test#destroy_user"
    get "/test/destroy_user_subscriptions", to: "admin_test#destroy_user_subscriptions"
    get "/test/travel_to_v2", to: "admin_test#travel_to_v2"
    get "/test/travel_back_v2", to: "admin_test#travel_back_v2"
    get "/test/wait_for_publish_posts_job", to: "admin_test#wait_for_publish_posts_job"
    get "/test/set_email_metadata", to: "admin_test#set_email_metadata"
    get "/test/assert_email_count_with_metadata", to: "admin_test#assert_email_count_with_metadata"
    get "/test/delete_email_metadata", to: "admin_test#delete_email_metadata"
    get "/test/execute_sql", to: "admin_test#execute_sql"
  end

  mount ActionCable.server => "/cable"

  # Avoid RoutingError with fatal log on 404
  match '*unmatched', to: 'application#route_not_found', via: :all
end
