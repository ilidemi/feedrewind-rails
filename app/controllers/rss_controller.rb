class RssController < ApplicationController
  def subscription_feed
    @subscription = Subscription.find(params[:id])
    @rss = SubscriptionRss.find_by(subscription_id: @subscription.id)
    render body: @rss.body, content_type: 'application/xml'
  end

  def user_feed
    @user = User.find(params[:id])
    @rss = UserRss.find_by(user_id: @user.id)
    render body: @rss.body, content_type: 'application/xml'
  end
end
