require_relative '../services/blog_fetch_service'

class BlogsController < ApplicationController
  def index
    @blogs = Blog.all
  end

  def create
    fetched_posts = BlogFetchService.fetch(
      blog_params[:url], blog_params[:list_xpath], blog_params[:link_xpath], blog_params[:title_xpath],
      blog_params[:date_xpath])

    Blog.transaction do
      @blog = Blog.new
      @blog.name = blog_params[:name]
      fetched_posts.each do |fetched_post|
        @blog.posts.new(link: fetched_post.link, title: fetched_post.title, date: fetched_post.date, is_sent: false)
      end
      @blog.save!
    end

    redirect_to root_path
  end

  def destroy
    @blog = Blog.find(params[:id])
    @blog.destroy!

    redirect_to root_path
  end

  def blog_params
    params.require(:new_blog).permit(:name, :url, :list_xpath, :link_xpath, :title_xpath, :date_xpath)
  end
end
