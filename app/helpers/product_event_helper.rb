module ProductEventHelper
  def ProductEventHelper::log_discover_feeds(request, product_user_id, user_is_anonymous, blog_url, result)
    ProductEvent::from_request!(
      request,
      product_user_id: product_user_id,
      event_type: "discover feeds",
      event_properties: {
        blog_url: blog_url,
        result: result,
        user_is_anonymous: user_is_anonymous
      }
    )
  end

  def ProductEventHelper::log_create_subscription(request, product_user_id, user_is_anonymous, subscription)
    ProductEvent::from_request!(
      request,
      product_user_id: product_user_id,
      event_type: "create subscription",
      event_properties: {
        subscription_id: subscription.id,
        blog_url: subscription.blog.best_url,
        is_blog_crawled: Blog::CRAWLED_STATUSES.include?(subscription.blog.status),
        user_is_anonymous: user_is_anonymous
      }
    )
  end

  def ProductEventHelper::log_schedule(
    request, product_user_id, event_type, subscription, weekly_count, active_days
  )
    ProductEvent::from_request!(
      request,
      product_user_id: product_user_id,
      event_type: event_type,
      event_properties: {
        subscription_id: subscription.id,
        blog_url: subscription.blog.best_url,
        weekly_count: weekly_count,
        active_days: active_days,
        posts_per_active_day: weekly_count.to_f / active_days
      }
    )
  end
end
