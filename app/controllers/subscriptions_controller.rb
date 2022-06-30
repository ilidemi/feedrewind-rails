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
    :create, :setup, :submit_progress_times, :all_posts, :confirm, :mark_wrong, :destroy
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
    :id, :name, :is_paused, :status, :version, :is_added_past_midnight, :url, :published_count, :total_count,
    :has_schedules, keyword_init: true
  )

  def show
    query = <<-SQL
      (
        select 'subscription' as tag, id, name, is_paused, status, version, is_added_past_midnight,
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
      version: first_row[5],
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
      @other_sub_names_by_day = get_other_sub_names_by_day(@subscription.id)
      @days_of_week = DAYS_OF_WEEK
      @schedule_preview = get_schedule_preview(@subscription, @current_user)
    end

    if @subscription.status == "live"
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
        local_date = timezone.utc_to_local(utc_now).to_date
        local_date_str = ScheduleHelper::date_str(local_date)

        # TODO: for email users this should be the email job? think more
        next_job_schedule_date = get_realistic_next_scheduled_date(
          UpdateRssJob, @current_user.id, local_date_str
        )
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

    subscription.transaction do
      subscription.create_subscription_posts_raw!
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

      @subscription.create_subscription_posts_raw!
      @subscription.status = "setup"
      @subscription.save!
    end

    redirect_to action: "setup", id: @subscription.id
  end

  def schedule
    # Initializing subscription feed may race with user's update rss job.
    # If the job is already running, wait till it finishes, otherwise lock the row so it doesn't start
    failed_lock_attempts = 0
    loop do
      result = ActiveRecord::Base.transaction do
        Rails.logger.info("Locking daily jobs")
        jobs = UserJobHelper::lock_daily_jobs(@current_user.id)
        Rails.logger.info("Locked daily jobs #{jobs}")

        unless jobs.all? { |job| job.locked_by.nil? }
          Rails.logger.info("Some jobs are running, unlocking #{jobs}")
          next
        end

        schedule_params = params.permit(:id, :name, *DAY_COUNT_NAMES)
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
        next_update_rss_job_date = UserJobHelper::get_next_scheduled_date(UpdateRssJob, @current_user.id)
        todays_update_rss_job_already_ran = next_update_rss_job_date > local_date_str
        next_email_posts_job_date = UserJobHelper::get_next_scheduled_date(EmailPostsJob, @current_user.id)
        todays_email_posts_job_already_ran = next_email_posts_job_date > local_date_str
        is_added_early_morning = ScheduleHelper.is_early_morning(local_datetime)
        should_publish_posts =
          todays_update_rss_job_already_ran &&
            is_added_early_morning &&
            !todays_email_posts_job_already_ran
        local_date = local_datetime.to_date

        @subscription.name = schedule_params[:name]
        @subscription.status = "live"
        @subscription.finished_setup_at = utc_now
        @subscription.version = 1
        @subscription.is_added_past_midnight = is_added_early_morning
        @subscription.save! # so that rss update can pick it up

        UpdateRssService.init_subscription(@subscription, should_publish_posts, utc_now, local_date)
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

    admin_votes = []
    other_votes = Set.new
    blog_votes.each do |vote|
      if is_admin(vote.user_id)
        admin_votes << [vote.user_id, vote.value]
      else
        other_votes << [vote.user_id, vote.value]
      end
    end
    dedup_blog_votes = admin_votes + other_votes.to_a

    return unless dedup_blog_votes.length >= 3

    confirmed_count = dedup_blog_votes.count { |_, value| value == "confirmed" }
    if confirmed_count * 1.0 / dedup_blog_votes.length > 0.5
      blog.status = "crawled_confirmed"
    else
      blog.status = "crawled_looks_wrong"
    end
    blog.status_updated_at = DateTime.now

    blog.save!
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
      # UpdateRssJob is always the source of truth for schedule preview
      next_schedule_date = get_realistic_next_scheduled_date(UpdateRssJob, user.id, local_date_str)
    end
    Rails.logger.info("Next schedule date: #{next_schedule_date}")

    SchedulePreview.new(
      prev_posts, next_posts, prev_has_more, next_has_more, local_date_str, next_schedule_date,
      user.user_settings.timezone
    )
  end

  def get_realistic_next_scheduled_date(job_class, user_id, local_date_str)
    next_schedule_date = UserJobHelper::get_next_scheduled_date(job_class, user_id)
    if next_schedule_date < local_date_str
      Rails.logger.warn("#{job_class} is scheduled in the past for user #{user_id}: #{next_schedule_date} (today is #{local_date_str})")
      local_date_str
    else
      next_schedule_date
    end
  end
end
