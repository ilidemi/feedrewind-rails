class CachedBlogs < ActiveRecord::Migration[6.1]
  def change
    rename_table("blogs", "old_blogs")
    rename_table("posts", "old_posts")

    reversible do |dir|
      dir.up { execute "alter type blog_status rename to old_blog_status" }
      dir.down { execute "alter type old_blog_status rename to blog_status" }
    end

    reversible do |dir|
      dir.up { execute "create type blog_status as enum ('crawl_in_progress', 'crawl_failed', 'crawled_voting', 'crawled_confirmed', 'crawled_looks_wrong')" }
      dir.down { execute "drop type blog_status" }
    end

    reversible do |dir|
      dir.up { execute "create type subscription_status as enum ('waiting_for_blog', 'setup', 'live')" }
      dir.down { execute "drop type subscription_status" }
    end

    reversible do |dir|
      dir.up { execute "create type blog_crawl_vote_value as enum ('confirmed', 'looks_wrong')" }
      dir.down { execute "drop type blog_crawl_vote_value" }
    end

    create_table :blogs do |t|
      t.string :name, null: false
      t.string :feed_url, null: false
      t.column :status, :blog_status, null: false
      t.datetime :status_updated_at, null: false
      t.integer :version, null: false

      t.timestamps
    end

    add_index(:blogs, [:feed_url, :version], unique: true)

    create_table :blog_crawl_votes do |t|
      t.uuid :user_id, null: true
      t.bigint :blog_id, null: false
      t.column :value, :blog_crawl_vote_value, null: false

      t.timestamps

      t.foreign_key :users
      t.foreign_key :blogs
    end

    create_table :blog_posts do |t|
      t.bigint :blog_id, null: false
      t.integer :index, null: false
      t.string :url, null: false
      t.string :title, null: false

      t.timestamps

      t.foreign_key :blogs
    end

    create_table :subscriptions do |t|
      t.uuid :user_id, null: true
      t.bigint :blog_id, null: false
      t.string :name, null: false
      t.column :status, :subscription_status, null: false
      t.boolean :is_paused
      t.boolean :is_added_past_midnight
      t.integer :last_post_index
      t.datetime :discarded_at

      t.timestamps

      t.foreign_key :blogs
      t.foreign_key :users
    end

    create_table :subscription_posts do |t|
      t.bigint :blog_post_id, null: false
      t.bigint :subscription_id, null: false
      t.boolean :is_published, null: false

      t.timestamps

      t.foreign_key :blog_posts
      t.foreign_key :subscriptions
    end

    rename_column(:schedules, :blog_id, :old_blog_id)
    rename_column(:blog_crawl_client_tokens, :blog_id, :old_blog_id)
    rename_column(:blog_crawl_progresses, :blog_id, :old_blog_id)
    rename_column(:current_rsses, :blog_id, :old_blog_id)

    add_column(:schedules, :subscription_id, :bigint)
    add_foreign_key(:schedules, :subscriptions)

    add_column(:current_rsses, :subscription_id, :bigint)
    add_foreign_key(:current_rsses, :subscriptions)

    add_column(:blog_crawl_client_tokens, :blog_id, :bigint)
    add_foreign_key(:blog_crawl_client_tokens, :blogs, name: "fk_rails_blogs")

    add_column(:blog_crawl_progresses, :blog_id, :bigint)
    add_foreign_key(:blog_crawl_progresses, :blogs, name: "fk_rails_blogs")

    reversible do |dir|
      dir.up do
        blog_status_map = {
          "crawl_in_progress" => "crawl_in_progress",
          "crawled" => "crawled_voting",
          "confirmed" => "crawled_confirmed",
          "live" => "crawled_confirmed",
          "crawl_failed" => "crawl_failed",
          "crawled_looks_wrong" => "crawled_looks_wrong"
        }

        subscription_status_map = {
          "crawl_in_progress" => "waiting_for_blog",
          "crawled" => "waiting_for_blog",
          "confirmed" => "setup",
          "live" => "live",
          "crawl_failed" => "waiting_for_blog",
          "crawled_looks_wrong" => "waiting_for_blog"
        }

        url_total_counts = OldBlog.with_discarded.map(&:url).tally
        url_processed_counts = {}

        OldBlog.with_discarded.order(:created_at).each do |old_blog|
          if url_processed_counts.key?(old_blog.url)
            url_processed_counts[old_blog.url] += 1
          else
            url_processed_counts[old_blog.url] = 1
          end

          if url_processed_counts[old_blog.url] == url_total_counts[old_blog.url]
            version = Blog::LATEST_VERSION
          else
            version = url_processed_counts[old_blog.url]
          end

          blog = Blog.create!(
            name: old_blog.name,
            feed_url: old_blog.url,
            status: blog_status_map[old_blog.status],
            status_updated_at: DateTime.now,
            version: version
          )

          max_post_index = OldPost.where(blog_id: old_blog.id).length - 1

          if old_blog.user_id
            subscription = Subscription.create!(
              blog_id: blog.id,
              user_id: old_blog.user_id,
              name: blog.name,
              status: subscription_status_map[old_blog.status],
              is_paused: old_blog.is_paused,
              is_added_past_midnight: old_blog.is_added_past_midnight,
              last_post_index: max_post_index
            )
          else
            subscription = nil
          end

          post_index = 0
          OldPost.where(blog_id: old_blog.id).order(:order).each do |old_post|
            blog_post = BlogPost.create!(
              blog_id: blog.id,
              index: post_index,
              url: old_post.link,
              title: old_post.title
            )

            if subscription
              SubscriptionPost.create!(
                blog_post_id: blog_post.id,
                subscription_id: subscription.id,
                is_published: old_post.is_published
              )
            end
            post_index += 1
          end

          if subscription
            Schedule.where(old_blog_id: old_blog.id).each do |schedule|
              schedule.subscription_id = subscription.id
              schedule.save!
            end

            CurrentRss.where(old_blog_id: old_blog.id).each do |current_rss|
              current_rss.subscription_id = subscription.id
              current_rss.save!
            end

            if old_blog.discarded_at
              subscription.discarded_at = old_blog.discarded_at
              subscription.save!
            end
          end

          BlogCrawlClientToken.where(old_blog_id: old_blog.id).each do |client_token|
            client_token.blog_id = blog.id
            client_token.save!
          end

          BlogCrawlProgress.where(old_blog_id: old_blog.id).each do |blog_crawl_progress|
            blog_crawl_progress.blog_id = blog.id
            blog_crawl_progress.save!
          end
        end
      end
    end

    change_column_null(:schedules, :subscription_id, false)
    change_column_null(:current_rsses, :subscription_id, false)
    change_column_null(:current_rsses, :body, false) # fixes existing issue
    change_column_null(:blog_crawl_client_tokens, :blog_id, false)
    change_column_null(:blog_crawl_progresses, :blog_id, false)

    reversible do |dir|
      dir.up do
        execute "alter table blog_crawl_client_tokens drop constraint blog_crawl_client_tokens_pkey;"
        execute "alter table blog_crawl_client_tokens add primary key (blog_id);"

        execute "alter table blog_crawl_progresses drop constraint blog_crawl_progresses_pkey;"
        execute "alter table blog_crawl_progresses add primary key (blog_id);"
      end

      dir.down do
        execute "alter table blog_crawl_client_tokens drop constraint blog_crawl_client_tokens_pkey;"
        execute "alter table blog_crawl_client_tokens add primary key (old_blog_id);"

        execute "alter table blog_crawl_progresses drop constraint blog_crawl_progresses_pkey;"
        execute "alter table blog_crawl_progresses add primary key (old_blog_id);"
      end
    end

    change_column_null(:schedules, :old_blog_id, true)
    change_column_null(:current_rsses, :old_blog_id, true)
    change_column_null(:blog_crawl_client_tokens, :old_blog_id, true)
    change_column_null(:blog_crawl_progresses, :old_blog_id, true)

    # Delete the old tables separately
  end
end
