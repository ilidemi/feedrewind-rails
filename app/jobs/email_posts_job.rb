require 'postmark'
require 'tzinfo'

class EmailPostsJob < ApplicationJob
  queue_as :default

  HOUR_OF_DAY = 5

  def perform(user_id, date_str, is_manual = false)
    user = User.find_by(id: user_id)
    unless user
      Rails.logger.info("User not found")
      return
    end

    if Rails.env.development? || Rails.env.test?
      test_metadata = TestSingleton.find("email_metadata")&.value
      if test_metadata
        api_token = Rails.application.credentials.postmark_api_sandbox_token
      else
        api_token = Rails.application.credentials.postmark_api_token
      end
    else
      test_metadata = nil
      api_token = Rails.application.credentials.postmark_api_token
    end
    postmark_client = Postmark::ApiClient.new(api_token)

    SubscriptionPost.transaction do
      posts_to_email = SubscriptionPost
        .where("published_at_local_date is not null and email_status is null")
        .includes(:subscription)
        .where(subscriptions: {user_id: user_id })
        .to_a

      post_count_by_date = posts_to_email
        .map(&:published_at_local_date)
        .each_with_object(Hash.new(0)) { |word, acc| acc[word] += 1 }

      if user.user_settings.delivery_channel != "email"
        Rails.logger.info("Posts to skip email: #{post_count_by_date}")
        posts_to_email.each do |subscription_post|
          subscription_post.email_status = "skipped"
          subscription_post.save!
        end
        next
      end

      Rails.logger.info("Posts to email: #{post_count_by_date}")
      if posts_to_email.empty?
        Rails.logger.info("Nothing to do")
        next
      end

      messages = []
      posts_to_email.each do |subscription_post|
        messages << SubscriptionPostMailer
          .with(subscription_post: subscription_post, test_metadata: test_metadata)
          .post_email
      end
      responses = postmark_client.deliver_messages(messages)

      sent, not_sent = posts_to_email
        .zip(messages, responses)
        .partition { |_, _, response| response[:error_code] == 0 }
      Rails.logger.info("Sent messages: #{sent.length}")
      not_sent.each do |_, message, response|
        # Possible reasons for partial failure:
        # Rate limit exceeded
        # Not allowed to sent (ran out of credits)
        # Too many batch messages (?)

        Rails.logger.warn("Error sending email: #{message.metadata} - #{response}")
      end

      raise "Failed to send: #{responses}" if sent.empty?

      not_sent.each do |subscription_post, _, _|
        subscription_post.email_status = "pending"
        subscription_post.save!
      end

      unless not_sent.empty?
        not_sent_post_ids = not_sent.map { |subscription_post, _, _| subscription_post.id }
        EmailPostsRetryJob.perform_later(user_id, not_sent_post_ids)
      end

      sent.each do |subscription_post, message, _|
        Rails.logger.info("Sent email: #{message.metadata}")
        subscription_post.email_status = "sent"
        subscription_post.save!
      end
    end

    unless is_manual
      date = Date.parse(date_str)
      UserJobHelper::schedule_for_tomorrow(EmailPostsJob, user, date, HOUR_OF_DAY)
    end
  end

  def self.initial_schedule(user)
    UserJobHelper::initial_daily_schedule(EmailPostsJob, user, HOUR_OF_DAY)
  end
end
