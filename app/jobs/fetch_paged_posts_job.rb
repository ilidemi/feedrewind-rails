require 'json'

class FetchPagedPostsJob < ApplicationJob
  queue_as :default

  def perform(blog_id, fetch_paged_params_json)
    fetch_paged_params = JSON.parse(fetch_paged_params_json, object_class: OpenStruct)
    blog = Blog.find(blog_id)
    next_order = blog.posts
                     .maximum("order") + 1

    FetchPostsService.fetch_paged(blog.url, fetch_paged_params) do |page_posts|
      page_posts.each do |post|
        blog.posts.new(link: post.link, order: next_order, title: post.title, date: post.date, is_sent: false)
        next_order += 1
      end
      blog.save!
    end

    blog.is_fetched = true
    blog.save!

    UpdateRssService.update_rss(blog.id)
    UpdateRssJob.schedule_for_tomorrow(blog.id)
  end
end

