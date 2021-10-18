require 'json'
require_relative '../jobs/guided_crawling_job'

class BlogsController < ApplicationController
  before_action :authorize

  DAY_COUNT_NAMES = [:sun_count, :mon_count, :tue_count, :wed_count, :thu_count, :fri_count, :sat_count]

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
  end

  def confirm
    @blog = @current_user.blogs.find(params[:id])

    return if @blog.status != "crawled"

    @blog.status = "confirmed"
    @blog.save!

    redirect_to action: "setup", id: @blog.id
  end

  def schedule
    schedule_params = params.permit(:id, :name, *DAY_COUNT_NAMES)

    total_count = DAY_COUNT_NAMES
      .map { |day_count_name| schedule_params[day_count_name].to_i }
      .sum
    raise "Expecting some count to not be zero" unless total_count > 0

    @blog = @current_user.blogs.find(schedule_params[:id])
    Blog.transaction do
      DAY_COUNT_NAMES.each do |day_count_name|
        day_count = schedule_params[day_count_name].to_i
        @blog.name = schedule_params[:name]
        @blog.schedules.new(
          day_of_week: day_count_name.to_s[...3],
          count: day_count
        )
        @blog.status = "live"
        @blog.save!
      end
      UpdateRssService.init(@blog)
    end

    redirect_to action: "setup", id: @blog.id
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
    update_params = params.permit(:id, *DAY_COUNT_NAMES)

    total_count = DAY_COUNT_NAMES
      .map { |day_count_name| update_params[day_count_name].to_i }
      .sum
    raise "Expecting some count to not be zero" unless total_count > 0

    @blog = @current_user.blogs.find(update_params[:id])
    Blog.transaction do
      DAY_COUNT_NAMES.each do |day_count_name|
        day_of_week = day_count_name.to_s[...3]
        day_count = update_params[day_count_name].to_i
        schedule = @blog.schedules.find_by(day_of_week: day_of_week)
        schedule.count = day_count
        schedule.save!
      end
    end

    redirect_to action: "show", id: @blog.id
  end

  def destroy
    @blog = @current_user.blogs.find(params[:id])
    @blog.destroy!

    redirect_to root_path
  end
end
