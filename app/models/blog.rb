require_relative '../lib/guided_crawling/extract_new_posts_from_feed'

class Blog < ApplicationRecord
  include RandomId

  LATEST_VERSION = 1000000

  has_one :blog_crawl_client_token, dependent: :destroy
  has_one :blog_crawl_progress, dependent: :destroy
  has_one :blog_post_lock, dependent: :destroy
  has_one :blog_canonical_equality_config, dependent: :destroy
  has_many :blog_crawl_votes, dependent: :destroy
  has_many :blog_posts, dependent: :destroy
  has_many :blog_discarded_feed_entries, dependent: :destroy

  # Invariants for a given feed_url:
  # If there is a good blog to use, it is always available at LATEST_VERSION
  # N blogs that are not LATEST_VERSION have versions 1..N
  # It is possible to not have a blog LATEST_VERSION if version N is crawl_failed/crawled_looks_wrong
  #
  # Invariant for a given feed_url + version:
  # Either status is crawl_in_progress/crawl_failed/crawled_looks_wrong or blog posts are filled out

  def Blog::create_or_update(start_page_id, start_feed_id, start_feed_url, name)
    def create_with_recrawling(start_page_id, start_feed_id, start_feed_url, name)
      blog = Blog.create!(
        name: name,
        feed_url: start_feed_url,
        status: "crawl_in_progress",
        status_updated_at: DateTime.now,
        version: Blog::LATEST_VERSION
      )

      BlogCrawlProgress.create!(blog_id: blog.id, epoch: 0)
      BlogPostLock.create!(blog_id: blog.id)
      GuidedCrawlingJob.perform_later(
        blog.id, GuidedCrawlingJobArgs.new(start_page_id, start_feed_id).to_json
      )

      blog
    end

    blog = Blog.find_by(feed_url: start_feed_url, version: Blog::LATEST_VERSION)

    unless blog
      begin
        Rails.logger.info("Creating a new blog for feed_url #{start_feed_url}")
        Blog.transaction do
          return create_with_recrawling(start_page_id, start_feed_id, start_feed_url, name)
        end
      rescue ActiveRecord::RecordNotUnique
        # Another writer must've created the record at the same time, let's use that
        blog = Blog.find_by(feed_url: start_feed_url, version: Blog::LATEST_VERSION)
        unless blog
          raise "Blog #{start_feed_url} with latest version didn't exist, then existed, now doesn't exist"
        end
      end
    end

    # A blog that is currently being crawled will come out fresh
    # A failed blog can't be fixed by updating
    return blog if %w[crawl_in_progress crawl_failed crawled_looks_wrong].include?(blog.status)

    # Update blog from feed
    start_feed = StartFeed.find(start_feed_id)
    blog_post_urls = blog
      .blog_posts
      .sort_by { |blog_post| -blog_post.index }
      .map(&:url)
    blog_curi_eq_cfg = blog.blog_canonical_equality_config
    curi_eq_cfg = CanonicalEqualityConfig.new(
      blog_curi_eq_cfg.same_hosts.to_set,
      blog_curi_eq_cfg.expect_tumblr_paths
    )
    discarded_feed_entry_urls = blog
      .blog_discarded_feed_entries
      .map(&:url)
    new_links = extract_new_posts_from_feed(
      start_feed.content, URI(start_feed_url), blog_post_urls, discarded_feed_entry_urls, curi_eq_cfg,
      Rails.logger
    )

    if new_links.nil?
      begin
        Rails.logger.info("Couldn't update the blog #{start_feed_url} from feed, recrawling")
        Blog.transaction do
          old_blog = blog
          old_blog.version = Blog::get_downgrade_version(start_feed_url)
          old_blog.save!
          return create_with_recrawling(start_page_id, start_feed_id, start_feed_url, name)
        end
      rescue ActiveRecord::RecordNotUnique
        # Another writer deprecated this blog at the same time
        blog = Blog.find_by(feed_url: start_feed_url, version: Blog::LATEST_VERSION)
        unless blog
          raise "Blog #{start_feed_url} with latest version was deprecated by another request but the latest version still doesn't exist"
        end
        blog
      end
    elsif new_links.empty?
      Rails.logger.info("Blog #{start_feed_url} doesn't need updating")
      blog
    else
      Rails.logger.info("Updating blog #{start_feed_url} with #{new_links.length} new links")
      begin
        blog.blog_post_lock.with_lock("for update nowait") do
          index_offset = blog.blog_posts.maximum(:index) + 1
          new_links.reverse.each_with_index do |link, index|
            BlogPost.create!(
              blog_id: blog.id,
              url: link.url,
              index: index + index_offset,
              title: link.title.value
            )
          end
        end
        blog.reload
      rescue ActiveRecord::LockWaitTimeout
        Rails.logger.info("Someone else is updating the blog posts for #{start_feed_url}, just waiting till they're done")
        blog.blog_post_lock.with_lock do
          # Just wait till the other writer is done
        end
        Rails.logger.info("Done waiting")

        # Assume that the other writer has put the fresh posts in
        # There could be a race condition where two updates and a post publish happened at the same time,
        # the other writer succeeds with an older list, the current writer fails with a newer list and ends up
        # using the older list. But if both updates came a second earlier, both would get the older list, and
        # the new post would still get published a second later, so the UX is the same and there's nothing we
        # could do about it.
        blog.reload
      end

      blog
    end
  end

  def Blog::get_downgrade_version(feed_url)
    Blog.where(feed_url: feed_url).length
  end

  def Blog::reset_failed_blogs(date_cutoff)
    blogs_to_reset = Blog
      .where("status = 'crawl_failed' or status = 'crawled_looks_wrong'")
      .where(["version = ?", Blog::LATEST_VERSION])
      .where(["status_updated_at < ?", date_cutoff])

    Rails.logger.info("Resetting #{blogs_to_reset.length} failed blogs")

    blogs_to_reset.each do |blog|
      blog.version = Blog::get_downgrade_version(blog.feed_url)
      Rails.logger.info("Blog #{blog.id} -> new version #{blog.version}")
      blog.save!
    end
  end

  def init_crawled(urls_titles, discarded_feed_urls, curi_eq_cfg_hash)
    raise "Can only init posts when status is crawl_in_progress" unless self.status == "crawl_in_progress"

    Blog.transaction do
      posts_count = urls_titles.length
      urls_titles.each_with_index do |url_title, post_index|
        self.blog_posts.create!(
          url: url_title[:url],
          index: posts_count - post_index - 1,
          title: url_title[:title],
        )
      end

      self.blog_canonical_equality_config.create!(
        blog_id: self.id,
        same_hosts: curi_eq_cfg_hash[:same_hosts],
        expect_tumblr_paths: curi_eq_cfg_hash[:expect_tumblr_paths]
      )
      discarded_feed_urls.each do |discarded_feed_url|
        self.blog_discarded_feed_entries.create!(
          blog_id: self.id,
          url: discarded_feed_url
        )
      end

      self.status = "crawled_voting"
      self.save!
    end
  end

  def destroy_recursively!
    Blog.transaction do
      Blog.uncached do
        blog_crawl_client_token.destroy! if blog_crawl_client_token
        blog_crawl_progress.destroy! if blog_crawl_progress
        blog_post_lock.destroy! if blog_post_lock
        blog_crawl_votes.destroy_all

        subscriptions = Subscription.with_discarded.where(blog_id: id)
        subscription_posts_relations = subscriptions
          .includes(:subscription_posts)
          .map(&:subscription_posts)

        subscription_posts_count = subscription_posts_relations.map(&:length).sum
        Rails.logger.info("Destroying #{subscription_posts_count} subscription posts")
        subscription_posts_relations.each do |subscription_posts|
          subscription_posts.destroy_all
        end

        Rails.logger.info("Destroying #{subscriptions.length} subscriptions")
        subscriptions.each do |subscription|
          subscription.discard!
          subscription.destroy_discarded!
        end

        blog_posts.destroy_all
        blog_discarded_feed_entries.destroy_all
        destroy!
      end
    end
  end
end
