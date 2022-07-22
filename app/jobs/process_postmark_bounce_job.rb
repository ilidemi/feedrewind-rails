class ProcessPostmarkBounceJob < ApplicationJob
  queue_as :default

  def perform(bounce_id)
    bounce = PostmarkBounce.find(bounce_id)

    if bounce.message_id.nil?
      Rails.logger.error("Bounce #{bounce_id} came without message_id")
      return
    end

    # If a bounce came before the message is saved, find will fail, the job will retry later and it's ok
    postmark_message = PostmarkMessage.find(bounce.message_id)

    user = postmark_message.subscription.user
    case bounce.bounce_type
    when "Subscribe", "AutoResponder", "OpenRelayTest"
      Rails.logger.info("Bounce is noise (#{bounce.bounce_type}), skipping")
      return
    when "Transient", "DnsError", "SoftBounce", "Undeliverable"
      Rails.logger.info("Soft bounce (#{bounce.bounce_type})")

      wait_times_by_attempt_count = {
        1 => 5.minutes,
        2 => 15.minutes,
        3 => 40.minutes,
        4 => 2.hours,
        5 => 3.hours,
        6 => 6.hours
      }

      attempt_count = PostmarkMessage
        .where(
          message_type: postmark_message.message_type,
          subscription_id: postmark_message.subscription_id,
          subscription_post_id: postmark_message.subscription_post_id
        )
        .count

      wait_time = wait_times_by_attempt_count[attempt_count]
      unless wait_time
        Rails.logger.error("Soft bounce after #{attempt_count} attempts, handling as hard bounce")
        mark_user_bounced(user, bounce)
        return
      end

      RetryBouncedEmailJob
        .set(wait: wait_time)
        .perform_later(bounce.message_id)
    else
      if %w[SpamNotification SpamComplaint ChallengeVerification].include?(bounce.bounce_type)
        Rails.logger.error("Spam complaint (#{bounce.bounce_type}), handling as hard bounce")
      else
        Rails.logger.error("Hard bounce (#{bounce.bounce_type})")
      end

      mark_user_bounced(user, bounce)
    end
  end

  private

  def mark_user_bounced(user, bounce)
    PostmarkBouncedUser.transaction do
      if PostmarkBouncedUser.exists?(user.id)
        Rails.logger.info("User #{user.id} already marked as bounced, nothing to do")
      else
        Rails.logger.info("Marking user #{user.id} as bounced")
        PostmarkBouncedUser.create!(user_id: user.id, example_bounce_id: bounce.id)
      end
    end
  end
end


