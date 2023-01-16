class RssController < ApplicationController
  def subscription_feed
    @subscription = Subscription.find(params[:id])
    @rss = SubscriptionRss.find_by(subscription_id: @subscription.id)
    if !@subscription.is_paused && @subscription.final_item_published_at.nil?
      product_rss_client = resolve_rss_client
      ProductEvent.create!(
        product_user_id: @subscription.user.product_user_id,
        event_type: "poll feed",
        event_properties: {
          subscription_id: @subscription.id,
          blog_url: @subscription.blog.best_url,
          feed_type: "subscription",
          client: product_rss_client
        }
      )
    end
    render body: @rss.body, content_type: 'application/xml'
  end

  def user_feed
    @user = User.find(params[:id])
    @rss = UserRss.find_by(user_id: @user.id)
    has_active_subscriptions = @user.subscriptions.any? do |sub|
      !sub.is_paused && sub.final_item_published_at.nil?
    end
    if has_active_subscriptions
      product_rss_client = resolve_rss_client
      ProductEvent.create!(
        product_user_id: @user.product_user_id,
        event_type: "poll feed",
        event_properties: {
          feed_type: "user",
          client: product_rss_client
        }
      )
    end
    render body: @rss.body, content_type: 'application/xml'
  end

  private

  def resolve_rss_client
    user_agent = request.user_agent
    if user_agent.start_with?("Feedly/")
      "Feedly"
    elsif user_agent.include?("inoreader.com;")
      "Inoreader"
    else
      user_agent
    end
  end
end
