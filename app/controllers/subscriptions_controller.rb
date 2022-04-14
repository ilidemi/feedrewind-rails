require 'json'
require 'timeout'
require_relative '../jobs/guided_crawling_job'
require_relative '../lib/guided_crawling/crawling'
require_relative '../lib/guided_crawling/http_client'
require_relative '../lib/guided_crawling/feed_discovery'

class SubscriptionsController < ApplicationController
  before_action :authorize, except: [
    :create, :setup, :submit_progress_times, :all_posts, :confirm, :mark_wrong, :destroy
  ]

  DAYS_OF_WEEK = %w[sun mon tue wed thu fri sat]
  DAY_COUNT_NAMES = [:sun_count, :mon_count, :tue_count, :wed_count, :thu_count, :fri_count, :sat_count]

  def index
    @subscriptions = @current_user.subscriptions.order(created_at: :desc)
  end

  def show
    @subscription = @current_user.subscriptions.find(params[:id])

    if @subscription.schedules.empty?
      redirect_to action: "setup", id: @subscription.id
    end

    @current_counts_by_day = @subscription
      .schedules
      .to_h { |schedule| [schedule.day_of_week, schedule.count] }
    @other_sub_names_by_day = get_other_sub_names_by_day(@subscription.id)
    @days_of_week = DAYS_OF_WEEK
  end

  def create
    fill_current_user
    create_params = params.permit(:start_feed_id)
    start_feed = StartFeed.find(create_params[:start_feed_id])

    # If the feed is already fetched, the blog and subscription were created in onboarding controller
    crawl_ctx = CrawlContext.new
    http_client = HttpClient.new(false)
    feed_result = fetch_feed_at_url(start_feed.url, true, crawl_ctx, http_client, Rails.logger)
    if feed_result.is_a?(Page)
      start_feed.content = feed_result.content
      start_feed.final_url = feed_result.fetch_uri.to_s
      start_feed.save!

      updated_blog = Blog::create_or_update(start_feed)
      subscription_or_blog_not_supported = Subscription::create_for_blog(updated_blog, @current_user)

      if subscription_or_blog_not_supported.is_a?(Subscription::BlogNotSupported)
        render plain: BlogsHelper.unsupported_path(subscription_or_blog_not_supported.blog)
      else
        render plain: SubscriptionsHelper.setup_path(subscription_or_blog_not_supported)
      end
    elsif [:discovered_bad_feed, :discovered_timeout_feed].include?(feed_result)
      render plain: "", status: :unsupported_media_type
    else
      raise "Unexpected result from fetch_feed_at_url: #{feed_result}"
    end
  end

  NextPosts = Struct.new(:blog_posts, :more_count)

  def setup
    fill_current_user
    @subscription = Subscription.find_by(id: params[:id])
    return redirect_from_not_found unless @subscription

    user_mismatch = redirect_if_user_mismatch(@subscription)
    return user_mismatch if user_mismatch

    if @current_user.nil? && !%w[waiting_for_blog setup].include?(@subscription.status)
      return redirect_to signup_path
    end

    if @current_user.nil?
      if !(@subscription.status == "waiting_for_blog" && @subscription.blog.status == "crawl_failed")
        cookies[:anonymous_subscription] = @subscription.id
      else
        cookies.delete(:anonymous_subscription)
      end
    end

    if @subscription.blog.status == "crawl_in_progress"
      @client_token_value = nil
      client_token = BlogCrawlClientToken.find_by(blog_id: @subscription.blog_id)

      unless client_token
        client_token_value = SecureRandom.random_bytes(8).unpack('h*').first # 8 bytes of lowercase hex
        begin
          BlogCrawlClientToken.create!(blog_id: @subscription.blog_id, value: client_token_value)
          @client_token_value = client_token_value
        rescue ActiveRecord::RecordNotUnique
          # Keep the value nil
        end
      end

      @blog_crawl_progress = BlogCrawlProgress.find(@subscription.blog_id)
    end

    if @subscription.status == "setup" && @current_user
      @other_sub_names_by_day = get_other_sub_names_by_day(nil)
      @days_of_week = DAYS_OF_WEEK

      next_blog_posts = @subscription
        .subscription_posts
        .includes(:blog_post)
        .order("blog_posts.index asc")
        .limit(3)
        .map(&:blog_post)
      more_count = @subscription.subscription_posts.length - next_blog_posts.length
      @next_posts = NextPosts.new(next_blog_posts, more_count)

      today = ScheduleHelper.today
      if today.is_early_morning
        first_schedule_time = today
      else
        first_schedule_time = today.advance_till_midnight
      end
      @today_date = today.date_str
      @first_schedule_date = first_schedule_time.date_str
    end
  end

  def progress
    fill_current_user

    subscription = Subscription.find(params[:id])
    return nil unless subscription.user_id == @current_user&.id

    result = Blog::crawl_progress_json(subscription.blog_id)

    respond_to do |format|
      format.json { render json: result }
    end
  end

  def submit_progress_times
    fill_current_user

    subscription = Subscription.find(params[:id])
    return nil unless subscription.user_id == @current_user&.id

    blog = subscription.blog
    client_token = blog.blog_crawl_client_token
    if params[:client_token] != client_token.value
      Rails.logger.info("Client token mismatch: incoming #{params[:client_token]}, expected #{client_token.value}")
      return nil
    end

    blog_crawl_progress = blog.blog_crawl_progress
    Rails.logger.info("Server: #{blog_crawl_progress.epoch_times}")
    Rails.logger.info("Client: #{params[:epoch_durations]}")
    server_durations = blog_crawl_progress
      .epoch_times
      &.split(";")
      &.map(&:to_f)
    client_durations = params[:epoch_durations]
      .split(";")
      .map(&:to_f)
    if client_durations.length != server_durations&.length
      Rails.logger.info("Epoch count mismatch: client #{client_durations.length}, server #{server_durations&.length}")
      return nil
    end

    avg_difference = client_durations
      .zip(server_durations)
      .map { |client_duration, server_duration| (client_duration - server_duration).abs }
      .sum / blog_crawl_progress.epoch
    Rails.logger.info("Avg full difference: #{avg_difference.round(3)}")

    client_durations_after_initial_load = client_durations
      .drop(1)
      .drop_while { |client_duration| client_duration == 0 }
      .drop(1)
    server_durations_after_initial_load = server_durations.last(client_durations_after_initial_load.length)

    avg_difference_after_initial_load = client_durations_after_initial_load
      .zip(server_durations_after_initial_load)
      .map { |client_duration, server_duration| (client_duration - server_duration).abs }
      .sum / blog_crawl_progress.epoch
    Rails.logger.info("Avg difference after initial load: #{avg_difference_after_initial_load.round(3)}")

    client_durations_initial_load = client_durations.take(
      client_durations.length - client_durations_after_initial_load.length
    )
    server_durations_initial_load = server_durations.take(client_durations_initial_load.length)
    initial_load_duration = server_durations_initial_load.sum - client_durations_initial_load.last
    Rails.logger.info("Initial load duration: #{initial_load_duration.round(3)}")

    nil
  end

  def all_posts
    fill_current_user
    subscription = Subscription.find_by(id: params[:id])
    return redirect_from_not_found unless subscription

    user_mismatch = redirect_if_user_mismatch(subscription)
    return user_mismatch if user_mismatch

    unless subscription.status == "waiting_for_blog" || (@current_user.nil? && subscription.status == "setup")
      return redirect_to action: "setup", id: subscription.id
    end

    @ordered_blog_posts = subscription
      .blog
      .blog_posts
      .sort_by(&:index)

    respond_to do |format|
      format.js
    end
  end

  def confirm
    fill_current_user
    subscription = Subscription.find_by(id: params[:id])
    return redirect_from_not_found unless subscription

    user_mismatch = redirect_if_user_mismatch(subscription)
    return user_mismatch if user_mismatch

    blog = subscription.blog
    unless subscription.status == "waiting_for_blog" &&
      %w[crawled_voting crawled_confirmed crawled_looks_wrong manually_inserted].include?(blog.status)

      return redirect_to action: "setup", id: subscription.id
    end

    BlogCrawlVote.create!(
      user_id: @current_user&.id,
      blog_id: blog.id,
      value: "confirmed"
    )

    commit_blog_votes(blog)

    SubscriptionPost.transaction do
      blog.blog_posts.each do |blog_post|
        SubscriptionPost.create!(
          blog_post_id: blog_post.id,
          subscription_id: subscription.id,
          is_published: false
        )
      end
    end

    subscription.status = "setup"
    subscription.save!

    if @current_user
      redirect_to action: "setup", id: subscription.id
    else
      redirect_to signup_path
    end
  end

  def mark_wrong
    fill_current_user
    @subscription = Subscription.find_by(id: params[:id])
    return redirect_from_not_found unless @subscription

    user_mismatch = redirect_if_user_mismatch(@subscription)
    return user_mismatch if user_mismatch

    blog = @subscription.blog
    unless @subscription.status == "waiting_for_blog" &&
      %w[crawled_voting crawled_confirmed crawled_looks_wrong manually_inserted].include?(blog.status)

      return redirect_to action: "setup", id: @subscription.id
    end

    BlogCrawlVote.create!(
      user_id: @current_user&.id,
      blog_id: blog.id,
      value: "looks_wrong"
    )

    commit_blog_votes(blog)

    render body: nil
  end

  def continue_with_wrong
    fill_current_user
    @subscription = Subscription.find_by(id: params[:id])
    return redirect_from_not_found unless @subscription

    user_mismatch = redirect_if_user_mismatch(@subscription)
    return user_mismatch if user_mismatch

    blog = @subscription.blog
    if @subscription.status == "waiting_for_blog" &&
      %w[crawled_voting crawled_confirmed crawled_looks_wrong manually_inserted].include?(blog.status)

      @subscription.status = "setup"
      @subscription.save!
    end

    redirect_to action: "setup", id: @subscription.id
  end

  def schedule
    schedule_params = params.permit(:id, :name, *DAY_COUNT_NAMES)

    @subscription = @current_user.subscriptions.find_by(id: schedule_params[:id])
    return redirect_from_not_found unless @subscription
    return if @subscription.status != "setup"

    total_count = DAY_COUNT_NAMES
      .map { |day_count_name| schedule_params[day_count_name].to_i }
      .sum
    raise "Expecting some count to not be zero" unless total_count > 0

    Subscription.transaction do
      DAY_COUNT_NAMES.each do |day_count_name|
        day_count = schedule_params[day_count_name].to_i
        @subscription.schedules.new(
          day_of_week: day_count_name.to_s[...3],
          count: day_count
        )
      end

      UpdateRssService.init(@subscription)

      if DateService.now.hour < 5
        # People setting up a blog just after midnight should still get it in the morning
        UpdateRssJob.perform_later(@subscription.id)
        @subscription.is_added_past_midnight = true
      else
        UpdateRssJob.schedule_for_tomorrow(@subscription.id)
        @subscription.is_added_past_midnight = false
      end

      @subscription.name = schedule_params[:name]
      @subscription.status = "live"
      @subscription.version = 1
      @subscription.save!
    end

    redirect_to action: "setup", id: @subscription.id
  end

  def pause
    @subscription = @current_user.subscriptions.find_by(id: params[:id])
    return redirect_from_not_found unless @subscription
    return if @subscription.status != "live"

    @subscription.is_paused = true
    @subscription.save!
    redirect_to action: 'show', id: @subscription.id
  end

  def unpause
    @subscription = @current_user.subscriptions.find_by(id: params[:id])
    return redirect_from_not_found unless @subscription
    return if @subscription.status != "live"

    @subscription.is_paused = false
    @subscription.save!
    redirect_to action: 'show', id: @subscription.id
  end

  def update
    update_params = params.permit(:id, :version, *DAY_COUNT_NAMES)
    @subscription = @current_user.subscriptions.find_by(id: update_params[:id])
    return redirect_from_not_found unless @subscription
    return if @subscription.status != "live"

    new_version = update_params[:version].to_i
    if @subscription.version >= new_version
      return render status: :conflict, json: { version: @subscription.version }
    end

    total_count = DAY_COUNT_NAMES
      .map { |day_count_name| update_params[day_count_name].to_i }
      .sum
    raise "Expecting some count to not be zero" unless total_count > 0

    Subscription.transaction do
      DAY_COUNT_NAMES.each do |day_count_name|
        day_of_week = day_count_name.to_s[...3]
        day_count = update_params[day_count_name].to_i
        schedule = @subscription.schedules.find_by(day_of_week: day_of_week)
        schedule.count = day_count
        schedule.save!
      end

      @subscription.version = new_version
      @subscription.save!
    end

    render head: :ok
  end

  def destroy
    fill_current_user
    @subscription = Subscription.find_by(id: params[:id])
    return redirect_from_not_found unless @subscription

    user_mismatch = redirect_if_user_mismatch(@subscription)
    return user_mismatch if user_mismatch

    @subscription.discard!

    if params[:redirect] == "add"
      redirect_to "/subscriptions/add"
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

  def redirect_if_user_mismatch(subscription)
    if subscription.user_id
      if @current_user.nil?
        return redirect_to login_path, alert: "Not authorized"
      elsif subscription.user_id != @current_user.id
        return redirect_to action: "index"
      end
    end
  end

  def commit_blog_votes(blog)
    blog_votes = BlogCrawlVote.where(blog_id: blog.id)
    return unless blog_votes.length >= 3

    confirmed_count = blog_votes.count { |vote| vote.value == "confirmed" }
    if confirmed_count * 1.0 / blog_votes.length > 0.5
      blog.status = "crawled_confirmed"
    else
      blog.status = "crawled_looks_wrong"
    end
    blog.status_updated_at = DateTime.now

    blog.save!
  end

  def get_other_sub_names_by_day(current_sub_id)
    other_active_subs = Subscription
      .includes(:subscription_posts)
      .includes(:schedules)
      .where(user_id: @current_user.id)
      .where(status: "live")
      .order("created_at desc")
      .filter { |sub| sub.id != current_sub_id }
      .filter { |sub| (sub.subscription_posts.count { |post| !post.is_published }) > 0 }

    other_sub_names_by_day = DAYS_OF_WEEK.to_h { |day| [day, []] }
    other_active_subs.each do |sub|
      sub.schedules.each do |schedule|
        schedule.count.times do
          other_sub_names_by_day[schedule.day_of_week] << sub.name
        end
      end
    end

    other_sub_names_by_day
  end
end
