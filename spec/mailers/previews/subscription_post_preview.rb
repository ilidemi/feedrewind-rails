# Preview all emails at http://localhost:3000/rails/mailers/subscription_post
class SubscriptionPostPreview < ActionMailer::Preview
  def post_email
    SubscriptionPostMailer.with(subscription_post: SubscriptionPost.first).post_email
  end
end
