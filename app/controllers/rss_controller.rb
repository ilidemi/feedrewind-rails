class RssController < ApplicationController
  def show
    @subscription = Subscription.find(params[:id])
    @rss = SubscriptionRss.find_by(subscription_id: @subscription.id)
    render body: @rss.body, content_type: 'application/xml'
  end
end
