class SubscriptionPost < ApplicationRecord
  belongs_to :subscription
  belongs_to :blog_post
end
