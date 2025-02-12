require 'addressable/uri'

module SubscriptionsHelper
  def SubscriptionsHelper.setup_path(subscription)
    "/subscriptions/#{subscription.id}/setup"
  end

  def SubscriptionsHelper.progress_path(subscription)
    "/subscriptions/#{subscription.id}/progress"
  end

  def SubscriptionsHelper.select_posts_path(subscription)
    "/subscriptions/#{subscription.id}/select_posts"
  end

  def SubscriptionsHelper.mark_wrong_path(subscription)
    "/subscriptions/#{subscription.id}/mark_wrong"
  end

  def SubscriptionsHelper.continue_with_wrong_path(subscription)
    "/subscriptions/#{subscription.id}/continue_with_wrong"
  end

  def SubscriptionsHelper.schedule_path(subscription)
    "/subscriptions/#{subscription.id}/schedule"
  end

  def SubscriptionsHelper.pause_path(subscription)
    "/subscriptions/#{subscription.id}/pause"
  end

  def SubscriptionsHelper.unpause_path(subscription)
    "/subscriptions/#{subscription.id}/unpause"
  end

  def SubscriptionsHelper.subscription_delete_path(subscription)
    "/subscriptions/#{subscription.id}/delete"
  end

  def SubscriptionsHelper.subscription_add_feed_path(feed_url)
    "/subscriptions/add/#{encode_url(feed_url)}"
  end

  def SubscriptionsHelper.subscription_add_url
    "https://feedrewind.com/subscriptions/add"
  end

  def SubscriptionsHelper.subscription_url(subscription)
    "https://feedrewind.com/subscriptions/#{subscription.id}"
  end

  def SubscriptionsHelper.subscription_path(subscription)
    "/subscriptions/#{subscription.id}"
  end

  # This has to be a full url because we're showing it to the user to select and copy
  def SubscriptionsHelper.feed_url(request, subscription)
    "#{request.protocol}#{request.host_with_port}/subscriptions/#{subscription.id}/feed"
  end

  def SubscriptionsHelper.encode_url(url)
    Addressable::URI.encode_component(url, Addressable::URI::CharacterClasses::UNRESERVED)
  end

  def SubscriptionsHelper.post_url(subscription_post)
    slug = SubscriptionsHelper.post_slug(subscription_post.blog_post.title)
    "https://feedrewind.com/posts/#{slug}/#{subscription_post.random_id}/"
  end

  def SubscriptionsHelper.post_slug(post_name)
    slug_tokens = post_name.downcase.scan(/\w+/)[...10]
    slug_length = slug_tokens.map(&:length).sum + slug_tokens.length - 1
    while slug_length > 100 and slug_tokens.length > 1
      slug_length -= (slug_tokens.last.length + 1)
      slug_tokens = slug_tokens[...-1]
    end
    if slug_length > 100
      slug_tokens.first[...100]
    else
      slug_tokens.join("-")
    end
  end

  class ProgressSaver
    def initialize(blog_id, feed_url)
      @blog_id = blog_id
      @feed_url = feed_url
      @last_epoch_timestamp = Time.now.utc
    end

    def save_status_and_count(status_str, count)
      BlogCrawlProgress.transaction do
        #noinspection RailsChecklist05
        blog_crawl_progress = BlogCrawlProgress.find(@blog_id)
        blog_crawl_progress.update_column(:progress, status_str)
        blog_crawl_progress.update_column(:count, count)
        new_epoch = blog_crawl_progress.epoch + 1
        blog_crawl_progress.update_column(:epoch, new_epoch)
        update_epoch_times(blog_crawl_progress)
        ActionCable.server.broadcast(
          "discovery_#{@blog_id}",
          { epoch: new_epoch, status: status_str, count: count }
        )
        Rails.logger.info("discovery_#{@blog_id} epoch: #{new_epoch} status: #{status_str} count: #{count}")
      end
    end

    def save_status(status_str)
      BlogCrawlProgress.transaction do
        #noinspection RailsChecklist05
        blog_crawl_progress = BlogCrawlProgress.find(@blog_id)
        blog_crawl_progress.update_column(:progress, status_str)
        new_epoch = blog_crawl_progress.epoch + 1
        blog_crawl_progress.update_column(:epoch, new_epoch)
        update_epoch_times(blog_crawl_progress)
        ActionCable.server.broadcast("discovery_#{@blog_id}", { epoch: new_epoch, status: status_str })
        Rails.logger.info("discovery_#{@blog_id} epoch: #{new_epoch} status: #{status_str}")
      end
    end

    def save_count(count)
      BlogCrawlProgress.transaction do
        #noinspection RailsChecklist05
        blog_crawl_progress = BlogCrawlProgress.find(@blog_id)
        blog_crawl_progress.update_column(:count, count)
        new_epoch = blog_crawl_progress.epoch + 1
        blog_crawl_progress.update_column(:epoch, new_epoch)
        update_epoch_times(blog_crawl_progress)
        ActionCable.server.broadcast("discovery_#{@blog_id}", { epoch: new_epoch, count: count })
        Rails.logger.info("discovery_#{@blog_id} epoch: #{new_epoch} count: #{count}")
      end
    end

    def emit_telemetry(regressions, kv_bag)
      AdminTelemetry.create!(
        key: "progress_regression",
        value: 1,
        extra: {
          blog_id: @blog_id,
          feed_url: @feed_url,
          regressions: regressions,
        }.merge(kv_bag)
      )
    end

    private

    def update_epoch_times(blog_crawl_progress)
      new_epoch_timestamp = Time.now.utc
      new_epoch_time = (new_epoch_timestamp - @last_epoch_timestamp).round(3)
      if blog_crawl_progress.epoch_times
        new_epoch_times = "#{blog_crawl_progress.epoch_times};#{new_epoch_time}"
      else
        new_epoch_times = "#{new_epoch_time}"
      end
      blog_crawl_progress.update_column(:epoch_times, new_epoch_times)
      @last_epoch_timestamp = new_epoch_timestamp
    end
  end
end
