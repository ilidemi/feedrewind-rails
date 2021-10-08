require 'json'
require_relative '../jobs/guided_crawling_job'

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
      :blog_name, :blog_url, :posts_per_day, :schedule_mon, :schedule_tue, :schedule_wed, :schedule_thu,
      :schedule_fri, :schedule_sat, :schedule_sun
    )

    days_of_week = BlogsHelper.days_of_week_from_params(create_params)
    raise "Days of week can't be empty" if days_of_week.empty?

    Blog.transaction do
      @blog = @current_user.blogs.new
      @blog.name = create_params[:blog_name]
      @blog.url = create_params[:blog_url]
      @blog.posts_per_day = create_params[:posts_per_day].to_i
      @blog.fetch_status = :in_progress
      @blog.is_paused = false
      days_of_week.each do |day_of_week|
        @blog.schedules.new(day_of_week: day_of_week)
      end
      @blog.save!

      GuidedCrawlingJob.perform_later(
        @blog.id, GuidedCrawlingJobArgs.new(create_params[:blog_url]).to_json
      )
    end

    redirect_to action: 'status', name: @blog.name
  end

  def status
    @blog = @current_user.blogs.find_by(name: params[:name])
    unless @blog
      return redirect_to action: 'index'
    end

    if @blog.fetch_status == "succeeded"
      redirect_to action: 'show', name: @blog.name
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
