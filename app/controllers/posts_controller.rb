class PostsController < ApplicationController
  def post
    subscription_post = SubscriptionPost.find_by!(random_id: params[:random_id])
    subscription = subscription_post.subscription
    ProductEvent.create!(
      product_user_id: subscription.user.product_user_id,
      event_type: "open post",
      event_properties: {
        subscription_id: subscription.id,
        blog_url: subscription.blog.best_url
      }
    )
    redirect_to subscription_post.blog_post.url
  end
end

