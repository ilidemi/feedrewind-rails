require 'json'
require_relative '../jobs/guided_crawling_job'

class BlogsController < ApplicationController
  before_action :authorize, except: [:create, :setup, :posts, :confirm, :mark_wrong, :destroy]

  DAY_COUNT_NAMES = [:sun_count, :mon_count, :tue_count, :wed_count, :thu_count, :fri_count, :sat_count]

  def index
    @blogs = @current_user.blogs.order(created_at: :desc)
  end

  def show
    @blog = @current_user.blogs.find(params[:id])

    if @blog.status != "live"
      redirect_to action: "setup", id: @blog.id
    end
  end

  def create
    fill_current_user
    create_params = params.permit(:start_page_id, :start_feed_id, :start_feed_final_url, :name)
    blog = BlogsHelper.create(
      create_params[:start_page_id], create_params[:start_feed_id], create_params[:start_feed_final_url],
      create_params[:name], @current_user
    )

    redirect_to BlogsHelper.setup_path(blog)
  end

  def setup
    fill_current_user
    @blog = Blog.find_by(id: params[:id])
    return redirect_from_not_found unless @blog

    user_mismatch = redirect_if_user_mismatch(@blog)
    return user_mismatch if user_mismatch

    if @current_user.nil? && !%w[crawl_in_progress crawled crawl_failed].include?(@blog.status)
      return redirect_to signup_path
    end

    if @current_user.nil?
      cookies[:unfinished_blog] = @blog.id
    end

    if @blog.status == "crawl_in_progress"
      @client_token_value = nil
      client_token = BlogCrawlClientToken.find_by(blog_id: @blog.id)
      unless client_token
        client_token_value = SecureRandom.random_bytes(8).unpack('h*').first
        begin
          BlogCrawlClientToken.create(blog_id: @blog.id, value: client_token_value)
          @client_token_value = client_token_value
        rescue ActiveRecord::RecordNotUnique
          # Keep the value nil
        end
      end

      @blog_crawl_progress = BlogCrawlProgress.find(@blog.id)
    end
  end

  def submit_progress_times
    fill_current_user

    client_token = BlogCrawlClientToken.find(params[:id])
    if params[:client_token] != client_token.value
      Rails.logger.info("Client token mismatch: incoming #{params[:client_token]}, expected #{client_token.value}")
      return nil
    end

    blog_crawl_progress = BlogCrawlProgress.find(params[:id])
    Rails.logger.info("Server: #{blog_crawl_progress.epoch_times}")
    Rails.logger.info("Client: #{params[:epoch_durations]}")
    server_epoch_durations = blog_crawl_progress
      .epoch_times
      .split(";")
      .map(&:to_f)
    client_epoch_durations = params[:epoch_durations]
      .split(";")
      .map(&:to_f)
    if client_epoch_durations.length != server_epoch_durations.length
      Rails.logger.info("Epoch count mismatch: client #{client_epoch_durations.length}, server #{server_epoch_durations.length}")
      return nil
    end

    avg_difference = client_epoch_durations
      .zip(server_epoch_durations)
      .map { |client_duration, server_duration| (client_duration - server_duration).abs }
      .sum / blog_crawl_progress.epoch
    Rails.logger.info("Avg full difference: #{avg_difference.round(3)}")

    client_epoch_durations_without_initial_load = client_epoch_durations
      .drop(1)
      .drop_while { |client_duration| client_duration == 0 }
      .drop(1)
    server_epoch_durations_without_initial_load =
      server_epoch_durations.last(client_epoch_durations_without_initial_load.length)

    avg_difference_without_initial_load = client_epoch_durations_without_initial_load
      .zip(server_epoch_durations_without_initial_load)
      .map { |client_duration, server_duration| (client_duration - server_duration).abs }
      .sum / blog_crawl_progress.epoch
    Rails.logger.info("Avg difference without initial load: #{avg_difference_without_initial_load.round(3)}")

    client_epoch_durations_initial_load = client_epoch_durations.take(
      client_epoch_durations.length - client_epoch_durations_without_initial_load.length
    )
    server_epoch_durations_initial_load = server_epoch_durations.take(
      client_epoch_durations_initial_load.length
    )
    initial_load_duration = server_epoch_durations_initial_load.sum - client_epoch_durations_initial_load.last
    Rails.logger.info("Initial load duration: #{initial_load_duration.round(3)}")

    nil
  end

  def posts
    fill_current_user
    @blog = Blog.find_by(id: params[:id])
    return redirect_from_not_found unless @blog

    user_mismatch = redirect_if_user_mismatch(@blog)
    return user_mismatch if user_mismatch

    return redirect_to BlogsHelper.setup_path(@blog) unless @blog.status == "crawled"

    respond_to do |format|
      format.js
    end
  end

  def confirm
    fill_current_user
    @blog = Blog.find_by(id: params[:id])
    return redirect_from_not_found unless @blog

    user_mismatch = redirect_if_user_mismatch(@blog)
    return user_mismatch if user_mismatch

    return if @blog.status != "crawled"

    @blog.status = "confirmed"
    @blog.save!

    if @current_user
      redirect_to action: "setup", id: @blog.id
    else
      redirect_to signup_path
    end
  end

  def mark_wrong
    fill_current_user
    @blog = Blog.find_by(id: params[:id])
    return redirect_from_not_found unless @blog

    user_mismatch = redirect_if_user_mismatch(@blog)
    return user_mismatch if user_mismatch

    return redirect_to BlogsHelper.setup_path(@blog) unless @blog.status == "crawled"

    @blog.looks_wrong = true
    @blog.save!

    respond_to do |format|
      format.js
    end
  end

  def schedule
    schedule_params = params.permit(:id, :name, *DAY_COUNT_NAMES)

    @blog = @current_user.blogs.find_by(id: schedule_params[:id])
    return redirect_from_not_found unless @blog
    return if @blog.status != "confirmed"

    total_count = DAY_COUNT_NAMES
      .map { |day_count_name| schedule_params[day_count_name].to_i }
      .sum
    raise "Expecting some count to not be zero" unless total_count > 0

    Blog.transaction do
      DAY_COUNT_NAMES.each do |day_count_name|
        day_count = schedule_params[day_count_name].to_i
        @blog.schedules.new(
          day_of_week: day_count_name.to_s[...3],
          count: day_count
        )
      end

      UpdateRssService.init(@blog)

      if DateService.now.hour < 5
        # People setting up a blog just after midnight should still get it in the morning
        UpdateRssJob.perform_later(@blog.id)
        @blog.is_added_past_midnight = true
      else
        UpdateRssJob.schedule_for_tomorrow(@blog.id)
        @blog.is_added_past_midnight = false
      end

      @blog.name = schedule_params[:name]
      @blog.status = "live"
      @blog.save!
    end

    redirect_to action: "setup", id: @blog.id
  end

  def pause
    @blog = @current_user.blogs.find_by(id: params[:id])
    return redirect_from_not_found unless @blog
    return if @blog.status != "live"

    @blog.is_paused = true
    @blog.save!
    redirect_to action: 'show', id: @blog.id
  end

  def unpause
    @blog = @current_user.blogs.find_by(id: params[:id])
    return redirect_from_not_found unless @blog
    return if @blog.status != "live"

    @blog.is_paused = false
    @blog.save!
    redirect_to action: 'show', id: @blog.id
  end

  def update
    update_params = params.permit(:id, *DAY_COUNT_NAMES)
    @blog = @current_user.blogs.find_by(id: update_params[:id])
    return redirect_from_not_found unless @blog
    return if @blog.status != "live"

    total_count = DAY_COUNT_NAMES
      .map { |day_count_name| update_params[day_count_name].to_i }
      .sum
    raise "Expecting some count to not be zero" unless total_count > 0

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
    fill_current_user
    @blog = Blog.find_by(id: params[:id])
    return redirect_from_not_found unless @blog

    user_mismatch = redirect_if_user_mismatch(@blog)
    return user_mismatch if user_mismatch

    @blog.discard!

    if params[:redirect] == "add"
      redirect_to "/blogs/add"
    else
      redirect_from_not_found
    end
  end

  private

  def redirect_from_not_found
    if @current_user.nil?
      redirect_to root_path
    else
      redirect_to action: "index"
    end
  end

  def redirect_if_user_mismatch(blog)
    if blog.user_id
      if @current_user.nil?
        return redirect_to login_path, alert: "Not authorized"
      elsif blog.user_id != @current_user.id
        return redirect_to action: "index"
      end
    end
  end
end
