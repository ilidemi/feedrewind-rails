class SubscriptionPostMailer < ApplicationMailer
  def initial_email
    @subscription = params[:subscription]

    metadata["user_id"] = @subscription.user_id
    metadata["subscription_id"] = @subscription.id

    test_metadata = params[:test_metadata]
    if test_metadata
      metadata["test"] = test_metadata
      metadata["server_timestamp"] = params[:server_timestamp]
    end

    mail(
      subject: "#{@subscription.name} added to FeedRewind",
      to: @subscription.user.email,
      message_stream: "outbound",
      tag: "subscription_initial"
    )
  end

  def post_email
    subscription_post = params[:subscription_post]
    @blog_post = subscription_post.blog_post
    @subscription = subscription_post.subscription

    metadata["user_id"] = @subscription.user_id
    metadata["subscription_id"] = @subscription.id
    metadata["subscription_post_id"] = subscription_post.id

    test_metadata = params[:test_metadata]
    if test_metadata
      metadata["test"] = test_metadata
      metadata["server_timestamp"] = params[:server_timestamp]
    end

    mail(
      subject: @blog_post.title,
      to: @subscription.user.email,
      message_stream: "outbound",
      tag: "subscription_post"
    )
  end

  def final_email
    @subscription = params[:subscription]

    metadata["user_id"] = @subscription.user_id
    metadata["subscription_id"] = @subscription.id

    test_metadata = params[:test_metadata]
    if test_metadata
      metadata["test"] = test_metadata
      metadata["server_timestamp"] = params[:server_timestamp]
    end

    mail(
      subject: "You're all caught up with #{@subscription.name}",
      to: @subscription.user.email,
      message_stream: "outbound",
      tag: "subscription_final"
    )
  end
end
