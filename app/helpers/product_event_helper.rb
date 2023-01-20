module ProductEventHelper
  def ProductEventHelper::log_visit_add_page(request, product_user_id, path, user_is_anonymous, extra = nil)
    event_properties = {
      path: path,
      referer: ProductEventHelper::collapse_referer(request.referer),
      user_is_anonymous: user_is_anonymous
    }
    event_properties.merge!(extra) if extra

    ProductEvent::from_request!(
      request,
      product_user_id: product_user_id,
      event_type: "visit add page",
      event_properties: event_properties
    )
  end

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

  def ProductEventHelper::collapse_referer(referer)
    return nil if referer.nil?

    begin
      referer_uri = URI(referer)
      if %w[feedrewind.com www.feedrewind.com feedrewind.herokuapp.com].include?(referer_uri.host)
        return "FeedRewind"
      end
    rescue
      # no-op
    end

    return referer
  end
end
