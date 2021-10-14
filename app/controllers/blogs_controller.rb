require 'json'
require_relative '../jobs/guided_crawling_job'

class BlogsController < ApplicationController
  before_action :authorize

  def index
    @blogs = @current_user.blogs
  end

  def show
    @blog = @current_user.blogs.find(params[:id])
  end

  def create
    create_params = params.permit(:start_page_id, :start_feed_id, :start_feed_final_url, :name)
    blog = BlogsHelper.create(
      create_params[:start_page_id], create_params[:start_feed_id], create_params[:start_feed_final_url],
      create_params[:name], @current_user
    )

    redirect_to BlogsHelper.setup_url(request, blog)
  end

  def setup
    @blog = @current_user.blogs.find(params[:id])
    unless @blog
      return redirect_to action: 'index'
    end

    if @blog.fetch_status == "succeeded"
      redirect_to action: 'show', id: @blog.id
    end
  end

  def pause
    @blog = @current_user.blogs.find(params[:id])
    @blog.is_paused = true
    @blog.save!
    redirect_to action: 'show', id: @blog.id
  end

  def unpause
    @blog = @current_user.blogs.find(params[:id])
    @blog.is_paused = false
    @blog.save!
    redirect_to action: 'show', id: @blog.id
  end

  def update
    update_params = params.permit(
      :id, :posts_per_day, :schedule_mon, :schedule_tue, :schedule_wed, :schedule_thu, :schedule_fri,
      :schedule_sat, :schedule_sun)

    @blog = @current_user.blogs.find(update_params[:id])
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
    @blog = @current_user.blogs.find(params[:id])
    @blog.destroy!

    redirect_to root_path
  end
end
