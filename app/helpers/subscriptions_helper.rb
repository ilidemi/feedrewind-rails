module SubscriptionsHelper
  def SubscriptionsHelper.setup_path(subscription)
    "/subscriptions/#{subscription.id}/setup"
  end

  def SubscriptionsHelper.all_posts_path(subscription)
    "/subscriptions/#{subscription.id}/all_posts"
  end

  def SubscriptionsHelper.confirm_path(subscription)
    "/subscriptions/#{subscription.id}/confirm"
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

  def SubscriptionsHelper.subscription_url(subscription)
    # TODO: this should become feeduler.com
    "https://rss-catchup.herokuapp.com/subscriptions/#{subscription.id}"
  end

  def SubscriptionsHelper.subscription_path(subscription)
    "/subscriptions/#{subscription.id}"
  end

  # This has to be a full url because we're showing it to the user to select and copy
  def SubscriptionsHelper.feed_url(request, subscription)
    "#{request.protocol}#{request.host_with_port}/subscriptions/#{subscription.id}/feed"
  end

  class ProgressSaver
    def initialize(blog_id)
      @blog_id = blog_id
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
