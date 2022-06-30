class SubscriptionPostMailer < ApplicationMailer
  def post_email
    subscription_post = params[:subscription_post]
    @blog_post = subscription_post.blog_post
    @subscription = subscription_post.subscription

    metadata["user_id"] = @subscription.user_id
    metadata["subscription_id"] = @subscription.id
    metadata["subscription_post_id"] = subscription_post.id

    test_metadata = params[:test_metadata]
    metadata["test"] = test_metadata if test_metadata

    mail(
      subject: @blog_post.title,
      to: @subscription.user.email,
      message_stream: "outbound",
      tag: "subscription_post"
    )
  end
end
