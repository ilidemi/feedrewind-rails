require_relative '../services/blog_fetch_service'
require_relative '../services/update_rss_service'

class BlogsController < ApplicationController
  def index
    @blogs = Blog.all
  end

  def create
    new_blog_params = params.require(:new_blog).permit(
      :name, :url, :list_xpath, :link_xpath, :title_xpath, :date_xpath, :paging_needed, :next_page_xpath,
      :page_order, :filtering_needed, :length_filter_xpath, :min_length, :posts_per_day, :schedule_mon, :schedule_tue,
      :schedule_wed, :schedule_thu, :schedule_fri, :schedule_sat, :schedule_sun)

    if new_blog_params[:paging_needed] == '1'
      paging_params = BlogFetchService::PagingParams.new(
        new_blog_params[:next_page_xpath], new_blog_params[:page_order])
    else
      paging_params = nil
    end

    if new_blog_params[:filtering_needed] == '1'
      filtering_params = BlogFetchService::FilteringParams.new(
        new_blog_params[:length_filter_xpath], new_blog_params[:min_length].to_i)
    else
      filtering_params = nil
    end

    fetch_params = BlogFetchService::FetchParams.new(
      new_blog_params[:url], new_blog_params[:list_xpath], new_blog_params[:link_xpath], new_blog_params[:title_xpath],
      new_blog_params[:date_xpath], paging_params, filtering_params)
    fetched_posts = BlogFetchService.fetch(fetch_params)

    days_of_week = []
    days_of_week << 'mon' if new_blog_params[:schedule_mon] == '1'
    days_of_week << 'tue' if new_blog_params[:schedule_tue] == '1'
    days_of_week << 'wed' if new_blog_params[:schedule_wed] == '1'
    days_of_week << 'thu' if new_blog_params[:schedule_thu] == '1'
    days_of_week << 'fri' if new_blog_params[:schedule_fri] == '1'
    days_of_week << 'sat' if new_blog_params[:schedule_sat] == '1'
    days_of_week << 'sun' if new_blog_params[:schedule_sun] == '1'

    Blog.transaction do
      @blog = Blog.new
      @blog.name = new_blog_params[:name]
      @blog.url = new_blog_params[:url]
      @blog.posts_per_day = new_blog_params[:posts_per_day].to_i
      fetched_posts.each_with_index do |fetched_post, post_index|
        @blog.posts.new(
          link: fetched_post.link, order: post_index, title: fetched_post.title, date: fetched_post.date,
          is_sent: false)
      end
      days_of_week.each do |day_of_week|
        @blog.schedules.new(day_of_week: day_of_week)
      end
      @blog.save!
    end

    UpdateRssService.update_rss(@blog.id)
    UpdateRssJob.schedule_for_tomorrow(@blog.id)

    redirect_to root_path
  end

  def destroy
    @blog = Blog.find(params[:id])
    @blog.destroy!

    redirect_to root_path
  end
end
