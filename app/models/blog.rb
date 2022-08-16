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
  has_many :blog_post_categories, dependent: :destroy

  # Invariants for a given feed_url:
  # If there is a good blog to use, it is always available at LATEST_VERSION
  # N blogs that are not LATEST_VERSION have versions 1..N
  # It is possible to not have a blog LATEST_VERSION if version N is
  # crawl_failed/update_from_feed_failed/crawled_looks_wrong
  #
  # Invariant for a given feed_url + version:
  # Either status is crawl_in_progress/crawl_failed/crawled_looks_wrong or blog posts are filled out

  def Blog::create_or_update(start_feed)
    blog = Blog.find_by(feed_url: start_feed.final_url, version: Blog::LATEST_VERSION)

    unless blog
      begin
        Rails.logger.info("Creating a new blog for feed_url #{start_feed.final_url}")
        Blog.transaction do
          blog = Blog::create_with_crawling(start_feed)
        end
        return blog
      rescue ActiveRecord::RecordNotUnique
        # Another writer must've created the record at the same time, let's use that
        blog = Blog.find_by(feed_url: start_feed.final_url, version: Blog::LATEST_VERSION)
        unless blog
          raise "Blog #{start_feed.final_url} with latest version didn't exist, then existed, now doesn't exist"
        end
      end
    end

    # A blog that is currently being crawled will come out fresh
    # A blog that failed crawl can't be fixed by updating
    # But a blog that failed update from feed can be retried, who knows
    return blog if %w[crawl_in_progress crawl_failed crawled_looks_wrong].include?(blog.status)

    # Update blog from feed
    blog_post_urls = blog
      .blog_posts
      .sort_by { |blog_post| -blog_post.index }
      .map(&:url)
    blog_post_curis = blog_post_urls.map { |url| to_canonical_link(url, logger).curi }
    blog_curi_eq_cfg = blog.blog_canonical_equality_config
    curi_eq_cfg = CanonicalEqualityConfig.new(
      blog_curi_eq_cfg.same_hosts.to_set,
      blog_curi_eq_cfg.expect_tumblr_paths
    )
    discarded_feed_entry_urls = blog
      .blog_discarded_feed_entries
      .map(&:url)
    new_links = extract_new_posts_from_feed(
      start_feed.content, URI(start_feed.final_url), blog_post_curis, discarded_feed_entry_urls, curi_eq_cfg,
      Rails.logger, Rails.logger
    )

    if new_links == []
      Rails.logger.info("Blog #{start_feed.final_url} doesn't need updating")
      return blog
    end

    if blog.update_action == "recrawl"
      begin
        Rails.logger.info("Blog #{start_feed.final_url} is marked to recrawl on update")
        Blog.transaction do
          old_blog = blog
          old_blog.version = Blog::get_downgrade_version(start_feed.final_url)
          old_blog.save!
          return Blog::create_with_crawling(start_feed)
        end
      rescue ActiveRecord::RecordNotUnique
        # Another writer deprecated this blog at the same time
        blog = Blog.find_by(feed_url: start_feed.final_url, version: Blog::LATEST_VERSION)
        unless blog
          raise "Blog #{start_feed.final_url} with latest version was deprecated by another request but the latest version still doesn't exist"
        end
        blog
      end
    elsif blog.update_action == "update_from_feed_or_fail"
      if new_links
        Rails.logger.info("Updating blog #{start_feed.final_url} from feed with #{new_links.length} new links")
        begin
          utc_now = DateTime.now.utc
          blog.blog_post_lock.with_lock("for update nowait") do
            index_offset = blog.blog_posts.maximum(:index) + 1
            blog_posts_fields = new_links.reverse.map.with_index do |link, index|
              {
                blog_id: blog.id,
                index: index + index_offset,
                url: link.url,
                title: link.title.value,
                created_at: utc_now,
                updated_at: utc_now
              }
            end
            BlogPost.insert_all!(blog_posts_fields)
          end
          blog.reload
        rescue ActiveRecord::LockWaitTimeout
          Rails.logger.info("Someone else is updating the blog posts for #{start_feed.final_url}, just waiting till they're done")
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
      else
        Rails.logger.info("Couldn't update blog #{start_feed.final_url} from feed, marking as failed")
        blog.status = "update_from_feed_failed"
        blog.save!
        blog
      end
    elsif blog.update_action == "fail"
      Rails.logger.info("Blog #{start_feed.final_url} is marked to fail on update")
      blog.status = "update_from_feed_failed"
      blog.save!
      blog
    elsif blog.update_action == "no_op"
      Rails.logger.info("Blog #{start_feed.final_url} is marked to never update")
      blog
    else
      raise "Unexpected blog update action: #{blog.update_action}"
    end
  end

  def Blog::get_downgrade_version(feed_url)
    Blog.where(feed_url: feed_url).length
  end

  def Blog::reset_failed_blogs(date_cutoff)
    blogs_to_reset = Blog
      .where("status in ('crawl_failed', 'crawled_looks_wrong', 'update_from_feed_failed')")
      .where(["version = ?", Blog::LATEST_VERSION])
      .where(["status_updated_at < ?", date_cutoff])

    Rails.logger.info("Resetting #{blogs_to_reset.length} failed blogs")

    blogs_to_reset.each do |blog|
      blog.version = Blog::get_downgrade_version(blog.feed_url)
      Rails.logger.info("Blog #{blog.id} -> new version #{blog.version}")
      blog.save!
    end
  end

  def init_crawled(url, urls_titles_categories, categories, discarded_feed_urls, curi_eq_cfg_hash)
    raise "Can only init posts when status is crawl_in_progress" unless self.status == "crawl_in_progress"

    Blog.transaction do
      posts_count = urls_titles_categories.length

      utc_now = DateTime.now.utc
      blog_posts_fields = urls_titles_categories.map.with_index do |url_title_categories, index|
        {
          blog_id: self.id,
          index: posts_count - index - 1,
          url: url_title_categories[:url],
          title: url_title_categories[:title],
          created_at: utc_now,
          updated_at: utc_now
        }
      end
      blog_post_ids = BlogPost.insert_all!(blog_posts_fields).map { |row| row["id"] }

      if categories.length > 0
        blog_post_categories_fields = categories.map.with_index do |category, index|
          {
            blog_id: self.id,
            name: category[:name],
            index: index,
            is_top: category[:is_top],
            created_at: utc_now,
            updated_at: utc_now
          }
        end
        category_ids = BlogPostCategory.insert_all!(blog_post_categories_fields).map { |row| row["id"] }

        category_ids_by_name = categories
          .zip(category_ids)
          .to_h { |category, category_id| [category[:name], category_id] }

        blog_posts_category_assignments_fields = urls_titles_categories
          .zip(blog_post_ids)
          .flat_map do |url_title_categories, blog_post_id|
          url_title_categories[:categories].map do |category_name|
            {
              blog_post_id: blog_post_id,
              category_id: category_ids_by_name[category_name],
              created_at: utc_now,
              updated_at: utc_now
            }
          end
        end
        BlogPostCategoryAssignment.insert_all!(blog_posts_category_assignments_fields)
      end

      BlogCanonicalEqualityConfig.create!(
        blog_id: self.id,
        same_hosts: curi_eq_cfg_hash[:same_hosts],
        expect_tumblr_paths: curi_eq_cfg_hash[:expect_tumblr_paths]
      )
      discarded_feed_urls.each do |discarded_feed_url|
        BlogDiscardedFeedEntry.create!(
          blog_id: self.id,
          url: discarded_feed_url
        )
      end

      self.url = url
      self.status = "crawled_voting"
      self.save!
    end
  end

  def Blog::crawl_progress_json(blog_id)
    BlogCrawlProgress.uncached do
      blog_crawl_progress = BlogCrawlProgress.find_by(blog_id: blog_id)
      unless blog_crawl_progress
        Rails.logger.info("Blog #{blog_id} crawl progress not found")
        return
      end

      Blog.uncached do
        blog_status = blog_crawl_progress.blog.status
        if blog_status == "crawl_in_progress"
          Rails.logger.info("Blog #{blog_id} crawl in progress (epoch #{blog_crawl_progress.epoch})")
          {
            epoch: blog_crawl_progress.epoch,
            status: blog_crawl_progress.progress,
            count: blog_crawl_progress.count
          }
        elsif %w[crawled_voting crawl_failed].include?(blog_status)
          Rails.logger.info("Blog #{blog_id} crawl done")
          { done: true }
        else
          Rails.logger.info("Unexpected blog status: #{blog_status}")
          { done: true }
        end
      end
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

  def downgrade!
    Blog.transaction do
      Blog.uncached do
        raise "Blog is not latest version: #{self.version}" if self.version != LATEST_VERSION

        self.version = Blog::get_downgrade_version(self.feed_url)
        self.save!
      end
    end
  end

  private

  def Blog::create_with_crawling(start_feed)
    blog = Blog.create!(
      name: start_feed.title,
      feed_url: start_feed.final_url,
      url: nil,
      status: "crawl_in_progress",
      status_updated_at: DateTime.now,
      version: Blog::LATEST_VERSION,
      update_action: "recrawl"
    )

    BlogCrawlProgress.create!(blog_id: blog.id, epoch: 0)
    BlogPostLock.create!(blog_id: blog.id)
    GuidedCrawlingJob.perform_later(
      blog.id, GuidedCrawlingJobArgs.new(start_feed.id).to_json
    )

    blog
  end
end
