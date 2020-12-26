require 'json'
require_relative '../services/fetch_posts_service'
require_relative '../services/update_rss_service'

class BlogsController < ApplicationController
  before_action :authorize

  def index
    @blogs = @current_user.blogs
  end

  def show
    @blog = @current_user.blogs.find_by(name: params[:name])
  end

  def create
    create_params = params.permit(
      :blog_name, :blog_url, :list_xpath, :link_xpath, :title_xpath, :date_xpath, :paging_needed,
      :next_page_xpath, :page_order, :filtering_needed, :length_filter_xpath, :min_length, :posts_per_day,
      :schedule_mon, :schedule_tue, :schedule_wed, :schedule_thu, :schedule_fri, :schedule_sat, :schedule_sun)

    if create_params[:paging_needed] == '1'
      paging_params = FetchPostsService::PagingParams.new(
        create_params[:next_page_xpath], create_params[:page_order])
    else
      paging_params = nil
    end

    if create_params[:filtering_needed] == '1'
      filtering_params = FetchPostsService::FilteringParams.new(
        create_params[:length_filter_xpath], create_params[:min_length].to_i)
    else
      filtering_params = nil
    end

    fetch_params = FetchPostsService::FetchParams.new(
      create_params[:blog_url], create_params[:list_xpath], create_params[:link_xpath], create_params[:title_xpath],
      create_params[:date_xpath], paging_params, filtering_params)
    fetch_result = FetchPostsService.fetch(fetch_params)
    fetched_posts = fetch_result[:posts]
    blog_is_fetched = fetch_result[:paged_params].nil?

    days_of_week = BlogsHelper.days_of_week_from_params(create_params)
    raise "Days of week can't be empty" if days_of_week.empty?

    Blog.transaction do
      @blog = @current_user.blogs.new
      @blog.name = create_params[:blog_name]
      @blog.url = create_params[:blog_url]
      @blog.posts_per_day = create_params[:posts_per_day].to_i
      @blog.is_fetched = blog_is_fetched
      @blog.is_paused = false
      fetched_posts.each_with_index do |fetched_post, post_index|
        @blog.posts.new(
          link: fetched_post.link, order: -post_index, title: fetched_post.title, date: fetched_post.date,
          is_published: false)
      end
      days_of_week.each do |day_of_week|
        @blog.schedules.new(day_of_week: day_of_week)
      end
      @blog.save!
    end

    if blog_is_fetched
      UpdateRssService.update_rss(@blog.id)
      UpdateRssJob.schedule_for_tomorrow(@blog.id)
      redirect_to root_path
    else
      FetchPagedPostsJob.perform_later(@blog.id, fetch_result[:paged_params].to_json)
      redirect_to action: 'status', name: @blog.name
    end
  end

  def status
    @blog = @current_user.blogs.find_by(name: params[:name])
    if @blog.is_fetched
      redirect_to root_path
    end
  end

  def pause
    @blog = @current_user.blogs.find_by(name: params[:name])
    @blog.is_paused = true
    @blog.save!
    redirect_to action: 'show', name: @blog.name
  end

  def unpause
    @blog = @current_user.blogs.find_by(name: params[:name])
    @blog.is_paused = false
    @blog.save!
    redirect_to action: 'show', name: @blog.name
  end

  def update
    update_params = params.permit(
      :name, :posts_per_day, :schedule_mon, :schedule_tue, :schedule_wed, :schedule_thu, :schedule_fri,
      :schedule_sat, :schedule_sun)

    @blog = @current_user.blogs.find_by!(name: update_params[:name])
    new_days_of_week = BlogsHelper.days_of_week_from_params(update_params)
                                  .to_set
    existing_days_of_week = @blog.schedules
                                 .select(:day_of_week)
                                 .map { |schedule| schedule[:day_of_week] }
                                 .to_set
    days_of_week_to_add = new_days_of_week - existing_days_of_week
    days_of_week_to_remove = existing_days_of_week - new_days_of_week

    Blog.transaction do
      @blog.posts_per_day = update_params[:posts_per_day].to_i
      days_of_week_to_add.each do |day_of_week|
        @blog.schedules.new(day_of_week: day_of_week)
      end
      days_of_week_to_remove.each do |day_of_week|
        @blog.schedules
             .where(day_of_week: day_of_week)
             .first
             .destroy!
      end
      @blog.save!
    end

    redirect_to root_path
  end

  def destroy
    @blog = @current_user.blogs.find_by(name: params[:name])
    @blog.destroy!

    redirect_to root_path
  end
end
