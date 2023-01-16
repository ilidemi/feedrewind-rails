require 'json'
require 'set'
require 'timeout'
require 'tzinfo'
require_relative '../jobs/guided_crawling_job'
require_relative '../lib/guided_crawling/crawling'
require_relative '../lib/guided_crawling/http_client'
require_relative '../lib/guided_crawling/feed_discovery'

class SubscriptionsController < ApplicationController
  before_action :authorize, except: [
    :create, :setup, :submit_progress_times, :select_posts, :mark_wrong, :delete
  ]

  DAYS_OF_WEEK = %w[sun mon tue wed thu fri sat]
  DAY_COUNT_NAMES = [:sun_count, :mon_count, :tue_count, :wed_count, :thu_count, :fri_count, :sat_count]

  IndexSubscription = Struct.new(:id, :name, :status, :is_paused, :published_count, :total_count)

  def index
    query = <<-SQL
      with user_subscriptions as (
        select id, name, status, is_paused, finished_setup_at, created_at from subscriptions
        where user_id = $1 and discarded_at is null
      )  
      select id, name, status, is_paused, published_count, total_count
      from user_subscriptions
      left join (
        select subscription_id,
          count(published_at) as published_count,
          count(1) as total_count
        from subscription_posts
        where subscription_id in (select id from user_subscriptions)
        group by subscription_id
      ) as post_counts on subscription_id = id
      order by finished_setup_at desc, created_at desc
    SQL
    query_result = ActiveRecord::Base.connection.exec_query(query, "SQL", [@current_user.id])
    subscriptions = query_result.rows.map { |row| IndexSubscription.new(*row) }
    @setting_up_subscriptions, set_up_subscriptions = subscriptions.partition do |subscription|
      subscription.status != "live"
    end
    @active_subscriptions, @finished_subscriptions = set_up_subscriptions.partition do |subscription|
      subscription.published_count < subscription.total_count
    end
    @subscriptions_count = subscriptions.length
  end

  ShowSubscription = Struct.new(
    :id, :name, :is_paused, :status, :schedule_version, :is_added_past_midnight, :url, :published_count,
    :total_count, :has_schedules, keyword_init: true
  )

  def show
    query = <<-SQL
      (
        select 'subscription' as tag, id, name, is_paused, status, schedule_version, is_added_past_midnight,
          (select url from blogs where id = blog_id) as url,
          (
            select count(published_at) from subscription_posts where subscription_id = subscriptions.id
          ) as published_count,
          (select count(1) from subscription_posts where subscription_id = subscriptions.id) as total_count,
          null::day_of_week, null::integer
        from subscriptions
        where id = $1 and user_id = $2 and discarded_at is null
      ) union all (
        select 'schedule' as tag, null, null, null, null, null, null, null, null, null, day_of_week, count
        from schedules
        where subscription_id = $1
      )
    SQL
    query_result = ActiveRecord::Base.connection.exec_query(query, "SQL", [params[:id], @current_user.id])
    unless query_result.rows.length > 0 && query_result.rows.first[0] == "subscription"
      return redirect_from_not_found
    end

    first_row = query_result.rows.first
    @subscription = ShowSubscription.new(
      id: first_row[1],
      name: first_row[2],
      is_paused: first_row[3],
      status: first_row[4],
      schedule_version: first_row[5],
      is_added_past_midnight: first_row[6],
      url: first_row[7],
      published_count: first_row[8],
      total_count: first_row[9],
    )

    if @subscription.status != "live"
      redirect_to action: "setup", id: @subscription.id
    end

    @current_counts_by_day = query_result.rows[1..].to_h { |row| [row[10], row[11]] }
    @other_sub_names_by_day = get_other_sub_names_by_day(@subscription.id)
    @days_of_week = DAYS_OF_WEEK
    @schedule_preview = get_schedule_preview(@subscription, @current_user)
    @delivery_channel = @current_user.user_settings.delivery_channel
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
      subscription_or_blog_not_supported = Subscription::create_for_blog(
        updated_blog, @current_user, @product_user_id
      )

      if subscription_or_blog_not_supported.is_a?(Subscription::BlogNotSupported)
        ProductEventHelper::log_discover_feeds(request, @product_user_id, start_feed.url, "known_unsupported")
        render plain: BlogsHelper.unsupported_path(subscription_or_blog_not_supported.blog)
      else
        subscription = subscription_or_blog_not_supported
        ProductEventHelper::log_discover_feeds(request, @product_user_id, start_feed.url, "feed")
        ProductEventHelper::log_create_subscription(request, @product_user_id, subscription)
        redirect_to SubscriptionsHelper.setup_path(subscription)
      end
    elsif feed_result == :discovered_bad_feed
      ProductEventHelper::log_discover_feeds(request, @product_user_id, start_feed.url, "bad_feed")
      render plain: "", status: :unsupported_media_type
    elsif feed_result == :discover_could_not_reach
      ProductEventHelper::log_discover_feeds(request, @product_user_id, start_feed.url, "could_not_reach")
      render plain: "", status: :unsupported_media_type
    else
      raise "Unexpected result from fetch_feed_at_url: #{feed_result}"
    end
  end

  TopCategory = Struct.new(:id, :name, :blog_posts)
  CustomCategory = Struct.new(:id, :name, :checked_count, :blog_posts)

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

    if @subscription.status == "waiting_for_blog" &&
      %w[crawled_voting crawled_confirmed crawled_looks_wrong manually_inserted].include?(
        @subscription.blog.status
      )

      all_categories = @subscription
        .blog
        .blog_post_categories
        .includes(:blog_post_category_assignments)
        .sort_by(&:index)
      top_categories, custom_categories = all_categories.partition { |category| category.is_top }

      @all_blog_posts = @subscription.blog.blog_posts.sort_by(&:index)
      blog_posts_by_id = {}
      @all_blog_posts.each do |blog_post|
        blog_posts_by_id[blog_post.id] = blog_post
      end

      @top_categories = []
      top_categories.each do |category|
        category_posts = category
          .blog_post_category_assignments
          .to_a
          .map { |assignment| blog_posts_by_id[assignment.blog_post_id] }
          .sort_by(&:index)
        @top_categories << TopCategory.new(category.id, category.name, category_posts)
      end

      #noinspection RubyNilAnalysis
      @checked_blog_post_ids = @top_categories.first.blog_posts.map(&:id).to_set
      #noinspection RubyNilAnalysis
      @checked_top_category_id = @top_categories.first.id
      #noinspection RubyNilAnalysis
      @checked_top_category_name = @top_categories.first.name
      @is_checked_everything = @top_categories.length == 1

      @custom_categories = []
      custom_categories.each do |category|
        category_posts = category
          .blog_post_category_assignments
          .to_a
          .map { |assignment| blog_posts_by_id[assignment.blog_post_id] }
          .sort_by(&:index)

        checked_count = category_posts.count { |blog_post| @checked_blog_post_ids.include?(blog_post.id) }

        @custom_categories << CustomCategory.new(category.id, category.name, checked_count, category_posts)
      end

    end

    if @subscription.status == "setup" && @current_user
      @other_sub_names_by_day = get_other_sub_names_by_day(@subscription.id)
      @days_of_week = DAYS_OF_WEEK
      @schedule_preview = get_schedule_preview(@subscription, @current_user)
      @delivery_channel_set = @current_user.user_settings.delivery_channel != nil
    end

    if @subscription.status == "live"
      @delivery_channel = @current_user.user_settings.delivery_channel
      published_count = @subscription.subscription_posts.where("published_at is not null").length
      if published_count == 1
        @arrival_message = :arrived_one
      elsif published_count > 1
        @arrival_message = :arrived_many
      else
        enabled_days_of_week = @subscription
          .schedules
          .where("count > 0")
          .to_h { |schedule| [schedule.day_of_week, schedule.count] }
        utc_now = DateTime.now.utc
        timezone = TZInfo::Timezone.get(@current_user.user_settings.timezone)
        local_datetime = timezone.utc_to_local(utc_now)
        local_date = local_datetime.to_date
        local_date_str = ScheduleHelper::date_str(local_date)

        next_job_schedule_date = get_realistic_next_scheduled_date(@current_user.id, local_datetime)
        todays_job_already_ran = next_job_schedule_date > local_date_str
        first_schedule_date = todays_job_already_ran ? local_date.next_day : local_date
        until enabled_days_of_week.include?(ScheduleHelper.day_of_week(first_schedule_date))
          first_schedule_date = first_schedule_date.next_day
        end

        @will_arrive_date = first_schedule_date.strftime("%A, %B %-d") + first_schedule_date.day.ordinal

        if enabled_days_of_week[ScheduleHelper.day_of_week(first_schedule_date)] == 1
          @arrival_message = :will_arrive_one
        else
          @arrival_message = :will_arrive_many
        end
      end
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

    std_deviation = (
      client_durations
        .zip(server_durations)
        .map { |client_duration, server_duration| (client_duration - server_duration) ** 2 }
        .sum / blog_crawl_progress.epoch
    ) ** 0.5
    Rails.logger.info("Standard deviation (full): #{std_deviation.round(3)}")

    client_durations_after_initial_load = client_durations
      .drop(1)
      .drop_while { |client_duration| client_duration == 0 }
      .drop(1)
    server_durations_after_initial_load = server_durations.last(client_durations_after_initial_load.length)

    std_deviation_after_initial_load = (
      client_durations_after_initial_load
        .zip(server_durations_after_initial_load)
        .map { |client_duration, server_duration| (client_duration - server_duration) ** 2 }
        .sum / blog_crawl_progress.epoch
    ) ** 0.5
    Rails.logger.info("Standard deviation after initial load: #{std_deviation_after_initial_load.round(3)}")
    AdminTelemetry.create!(
      key: "progress_timing_std_deviation",
      value: std_deviation_after_initial_load,
      extra: {
        feed_url: blog.feed_url,
        subscription_id: subscription.id
      }
    )

    # E2E for crawling job getting picked up and reporting the first rectangle
    initial_load_duration = client_durations.first
    if initial_load_duration > 10
      Rails.logger.warn("Initial load duration (exceeds 10 seconds): #{initial_load_duration.round(3)}")
    else
      Rails.logger.info("Initial load duration: #{initial_load_duration.round(3)}")
    end
    AdminTelemetry.create!(
      key: "progress_timing_initial_load",
      value: initial_load_duration,
      extra: {
        feed_url: blog.feed_url,
        subscription_id: subscription.id
      }
    )

    # Just the establishing websocket part, at the granularity of throttled crawl requests
    websocket_wait_duration = [0.0, params[:websocket_wait_duration].to_f - server_durations.first].max
    Rails.logger.info("Websocket wait duration: #{websocket_wait_duration.round(3)}")
    AdminTelemetry.create!(
      key: "websocket_wait_duration",
      value: websocket_wait_duration,
      extra: {
        feed_url: blog.feed_url,
        subscription_id: subscription.id
      }
    )

    nil
  end

  def select_posts
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

    top_category_id = nil
    top_category = nil
    blog_post_ids = []
    if params[:top_category_id] != ""
      top_category_id = params[:top_category_id].to_i
      top_category = BlogPostCategory.find_by(id: top_category_id, blog_id: blog.id)
      if top_category.nil?
        raise "Category not found: #{top_category_id}"
      end
    else
      params.keys.each do |key|
        next unless key.start_with?("post_")
        next unless params[key] == "1"

        blog_post_ids << Integer(key[5..])
      end
    end

    if params[:looks_wrong] != "1"
      BlogCrawlVote.create!(
        user_id: @current_user&.id,
        blog_id: blog.id,
        value: "confirmed"
      )
    end

    product_selected_count = top_category ?
      top_category.blog_post_category_assignments.count :
      blog_post_ids.length
    total_posts_count = blog.blog_posts.count
    product_selection = top_category ?
      top_category.name == "Everything" ?
        "everything" :
        "top_category" :
      "custom"
    ProductEvent::from_request!(
      request,
      product_user_id: @product_user_id,
      event_type: "select posts",
      event_properties: {
        subscription_id: subscription.id,
        blog_url: subscription.blog.best_url,
        selected_count: product_selected_count,
        selected_fraction: product_selected_count.to_f / total_posts_count,
        selection: product_selection
      }
    )

    subscription.transaction do
      if top_category_id
        subscription.create_subscription_posts_from_category_raw!(top_category_id)
      else
        subscription.create_subscription_posts_from_ids_raw!(blog_post_ids)
      end
      subscription.status = "setup"
      subscription.save!
    end

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

    ProductEvent::from_request!(
      request,
      product_user_id: @product_user_id,
      event_type: "mark wrong",
      event_properties: {
        subscription_id: @subscription.id,
        blog_url: @subscription.blog.best_url
      }
    )

    Rails.logger.warn("Blog #{blog.id} (#{blog.name}) marked as wrong")

    render body: nil
  end

  def schedule
    # Initializing subscription feed may race with user's update rss job.
    # If the job is already running, wait till it finishes, otherwise lock the row so it doesn't start
    failed_lock_attempts = 0
    loop do
      result = ActiveRecord::Base.transaction do
        Rails.logger.info("Locking daily jobs")
        jobs = PublishPostsJob::lock(@current_user.id)
        Rails.logger.info("Locked daily jobs #{jobs}")

        unless jobs.all? { |job| job.locked_by.nil? }
          Rails.logger.info("Some jobs are running, unlocking #{jobs}")
          next
        end

        schedule_params = params.permit(:id, :name, *DAY_COUNT_NAMES, :delivery_channel)
        @subscription = @current_user.subscriptions.find_by(id: schedule_params[:id])
        return redirect_from_not_found unless @subscription
        return if @subscription.status != "setup"

        counts_by_day = DAYS_OF_WEEK.zip(DAY_COUNT_NAMES).to_h do |day_of_week, day_count_name|
          [day_of_week, schedule_params[day_count_name].to_i]
        end

        total_count = counts_by_day
          .values
          .sum
        raise "Expecting some count to not be zero" unless total_count > 0

        user_settings = @current_user.user_settings
        if schedule_params[:delivery_channel]
          case schedule_params[:delivery_channel]
          when "rss"
            user_settings.delivery_channel = "multiple_feeds"
          when "email"
            user_settings.delivery_channel = "email"
          else
            raise "Unknown delivery channel: #{schedule_params[:delivery_channel]}"
          end
          user_settings.save!
          PublishPostsJob.initial_schedule(@current_user)
          ProductEvent::from_request!(
            request,
            product_user_id: @product_user_id,
            event_type: "pick delivery channel",
            event_properties: {
              channel: user_settings.delivery_channel
            },
            user_properties: {
              delivery_channel: user_settings.delivery_channel
            }
          )
        elsif user_settings.delivery_channel.nil?
          raise "Delivery channel is not set for the user and is not passed in the params"
        end

        counts_by_day.each do |day_of_week, count|
          @subscription.schedules.create!(
            day_of_week: day_of_week,
            count: count
          )
        end

        utc_now = DateTime.now.utc
        timezone = TZInfo::Timezone.get(@current_user.user_settings.timezone)
        local_datetime = timezone.utc_to_local(utc_now)
        local_date_str = ScheduleHelper.date_str(local_datetime)

        # If subscription got added early morning, the first post needs to go out the same day, either via the
        # daily job or right away if the update rss job has already ran
        next_job_date = PublishPostsJob::get_next_scheduled_date(@current_user.id)
        todays_job_already_ran = next_job_date > local_date_str
        is_added_early_morning = ScheduleHelper.is_early_morning(local_datetime)
        should_publish_rss_posts = todays_job_already_ran && is_added_early_morning
        local_date = local_datetime.to_date

        @subscription.name = schedule_params[:name]
        @subscription.status = "live"
        @subscription.finished_setup_at = utc_now
        @subscription.schedule_version = 1
        @subscription.is_added_past_midnight = is_added_early_morning
        @subscription.save! # so that publish posts service can pick it up

        PublishPostsService.init_subscription(
          @subscription, should_publish_rss_posts, utc_now, local_date, local_date_str
        )

        product_active_days = counts_by_day.count { |_, count| count > 0 }
        ProductEventHelper::log_schedule(
          request, @product_user_id, "schedule", @subscription, total_count, product_active_days
        )

        slack_email = NotifySlackJob::escape(@current_user.email)
        blog = @subscription.blog
        slack_blog_url = NotifySlackJob::escape(blog.best_url)
        slack_blog_name = NotifySlackJob::escape(blog.name)
        NotifySlackJob.perform_later(
          "*#{slack_email}* subscribed to *<#{slack_blog_url}|#{slack_blog_name}>*"
        )

        Rails.logger.info("Unlocked daily jobs #{jobs}")
        render plain: SubscriptionsHelper.setup_path(@subscription)
      end

      return result if result

      failed_lock_attempts += 1
      if failed_lock_attempts >= 3
        raise "Couldn't lock the job rows"
      end
      sleep(1)
    end
  end

  def pause
    @subscription = @current_user.subscriptions.find_by(id: params[:id])
    return redirect_from_not_found unless @subscription
    return if @subscription.status != "live"

    @subscription.is_paused = true
    @subscription.save!

    ProductEvent::from_request!(
      request,
      product_user_id: @product_user_id,
      event_type: "pause subscription",
      event_properties: {
        subscription_id: @subscription.id,
        blog_url: @subscription.blog.best_url
      }
    )
    head :ok
  end

  def unpause
    @subscription = @current_user.subscriptions.find_by(id: params[:id])
    return redirect_from_not_found unless @subscription
    return if @subscription.status != "live"

    @subscription.is_paused = false
    @subscription.save!

    ProductEvent::from_request!(
      request,
      product_user_id: @product_user_id,
      event_type: "unpause subscription",
      event_properties: {
        subscription_id: @subscription.id,
        blog_url: @subscription.blog.best_url
      }
    )
    head :ok
  end

  def update
    update_params = params.permit(:id, :schedule_version, *DAY_COUNT_NAMES)
    @subscription = @current_user.subscriptions.find_by(id: update_params[:id])
    return redirect_from_not_found unless @subscription
    return if @subscription.status != "live"

    new_version = update_params[:schedule_version].to_i
    if @subscription.schedule_version >= new_version
      return render status: :conflict, json: { schedule_version: @subscription.schedule_version }
    end

    total_count = DAY_COUNT_NAMES
      .map { |day_count_name| update_params[day_count_name].to_i }
      .sum
    raise "Expecting some count to not be zero" unless total_count > 0

    Subscription.transaction do
      product_active_days = 0
      DAY_COUNT_NAMES.each do |day_count_name|
        day_of_week = day_count_name.to_s[...3]
        day_count = update_params[day_count_name].to_i
        product_active_days += 1 if day_count > 0
        schedule = @subscription.schedules.find_by(day_of_week: day_of_week)
        schedule.count = day_count
        schedule.save!
      end

      @subscription.schedule_version = new_version
      @subscription.save!

      ProductEventHelper::log_schedule(
        request, @product_user_id, "update schedule", @subscription, total_count, product_active_days
      )
    end

    head :ok
  end

  def delete
    fill_current_user
    @subscription = Subscription.find_by(id: params[:id])
    return redirect_from_not_found unless @subscription

    user_mismatch = redirect_if_user_mismatch(@subscription)
    return user_mismatch if user_mismatch

    @subscription.discard!

    ProductEvent::from_request!(
      request,
      product_user_id: @product_user_id,
      event_type: "delete subscription",
      event_properties: {
        subscription_id: @subscription.id,
        blog_url: @subscription.blog.best_url
      }
    )

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
        return redirect_to SessionsHelper::login_path_with_redirect(request)
      elsif subscription.user_id != @current_user.id
        return redirect_to action: "index"
      end
    end
  end

  def get_other_sub_names_by_day(current_sub_id)
    query = <<-SQL
      with user_subscriptions as (
        select id, name, created_at from subscriptions
        where user_id = $1 and
          status = 'live' and
          discarded_at is null
      )  
      select name, day_of_week, day_count
      from user_subscriptions
      join (
        select subscription_id,
          count(published_at) as published_count,
          count(1) as total_count
        from subscription_posts
        where subscription_id in (select id from user_subscriptions)
        group by subscription_id
      ) as post_counts on post_counts.subscription_id = id
      join (
        select subscription_id, day_of_week, count as day_count
        from schedules
        where count > 0 and subscription_id in (select id from user_subscriptions)
      ) as schedules on schedules.subscription_id = id
      where id != $2 and published_count != total_count
      order by created_at desc
    SQL
    query_result = ActiveRecord::Base.connection.exec_query(query, "SQL", [@current_user.id, current_sub_id])

    other_sub_names_by_day = DAYS_OF_WEEK.to_h { |day| [day, []] }
    query_result.rows.each do |row|
      name, day_of_week, day_count = *row
      day_count.times do
        other_sub_names_by_day[day_of_week] << name
      end
    end

    other_sub_names_by_day
  end

  SchedulePreview = Struct.new(
    :prev_posts, :next_posts, :prev_has_more, :next_has_more, :today_date, :next_schedule_date, :timezone
  )
  PrevPost = Struct.new(:url, :title, :published_date, keyword_init: true)
  NextPost = Struct.new(:url, :title, keyword_init: true)

  def get_schedule_preview(subscription, user)
    query = <<-SQL
      (
        select
          'prev_post' as tag,
          url,
          title,
          published_at_local_date,
          null::bigint as count
        from subscription_posts
        join (select id, url, title, index from blog_posts) as blog_posts on blog_posts.id = blog_post_id 
        where subscription_id = $1 and published_at is not null
        order by index desc
        limit 2
      ) UNION ALL (
        select 'next_post' as tag, url, title, published_at_local_date, null as count
        from subscription_posts
        join (select id, url, title, index from blog_posts) as blog_posts on blog_posts.id = blog_post_id 
        where subscription_id = $1 and published_at is null
        order by index asc
        limit 5
      ) UNION ALL (
        select 'published_count' as tag, null, null, null, count(published_at) as count from subscription_posts
        where subscription_id = $1
      ) UNION ALL (
        select 'total_count' as tag, null, null, null, count(1) as count from subscription_posts
        where subscription_id = $1
      )
    SQL
    query_result = ActiveRecord::Base.connection.exec_query(query, "SQL", [subscription.id])

    prev_posts = []
    next_posts = []
    published_count = nil
    total_count = nil

    query_result.rows.each do |row|
      if row[0] == "prev_post"
        prev_posts << PrevPost.new(
          url: row[1],
          title: row[2],
          published_date: row[3]
        )
      elsif row[0] == "next_post"
        next_posts << NextPost.new(
          url: row[1],
          title: row[2]
        )
      elsif row[0] == "published_count"
        published_count = row.last.to_i
      elsif row[0] == "total_count"
        total_count = row.last.to_i
      end
    end

    prev_posts.reverse!
    unpublished_count = total_count - published_count

    prev_has_more = (published_count - prev_posts.length) > 0
    if prev_has_more
      # Always show 2 lines: either all 2 prev posts or ellipsis and a post
      prev_posts = prev_posts[1..]
    end

    next_has_more = (unpublished_count - next_posts.length) > 0
    if next_has_more
      # Always show 5 lines: either all 5 next posts or 4 posts and ellipsis
      next_posts = next_posts[...-1]
    end

    utc_now = DateTime.now.utc
    timezone = TZInfo::Timezone.get(user.user_settings.timezone)
    local_datetime = timezone.utc_to_local(utc_now)
    local_date_str = ScheduleHelper::date_str(local_datetime)

    if subscription.status != "live" && ScheduleHelper::is_early_morning(local_datetime)
      next_schedule_date = local_date_str
    else
      next_schedule_date = get_realistic_next_scheduled_date(user.id, local_datetime)
    end
    Rails.logger.info("Next schedule date: #{next_schedule_date}")

    SchedulePreview.new(
      prev_posts, next_posts, prev_has_more, next_has_more, local_date_str, next_schedule_date,
      user.user_settings.timezone
    )
  end

  def get_realistic_next_scheduled_date(user_id, local_datetime)
    next_schedule_date = PublishPostsJob::get_next_scheduled_date(user_id)
    local_date_str = ScheduleHelper::date_str(local_datetime)
    if next_schedule_date.nil?
      if ScheduleHelper::is_early_morning(local_datetime)
        local_date_str
      else
        ScheduleHelper::date_str(local_datetime.to_date.next_day)
      end
    elsif next_schedule_date < local_date_str
      Rails.logger.warn("Job is scheduled in the past for user #{user_id}: #{next_schedule_date} (today is #{local_date_str})")
      local_date_str
    else
      next_schedule_date
    end
  end
end
