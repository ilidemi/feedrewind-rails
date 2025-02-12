require 'postmark'
require 'tzinfo'

class EmailPostsJob < ApplicationJob
  queue_as :default

  def perform(user_id, date_str, scheduled_for_str, final_item_subscription_ids)
    not_sent_count = SubscriptionPost.transaction do
      user = User.find_by(id: user_id)
      unless user
        Rails.logger.info("User #{user_id} not found")
        return
      end

      if PostmarkBouncedUser.exists?(user_id)
        Rails.logger.info("User #{user_id} marked as bounced, not sending anything")
        return
      end

      posts_to_email = SubscriptionPost
        .where(publish_status: "email_pending")
        .includes(:subscription)
        .where(subscriptions: { user_id: user_id })
        .to_a

      post_count_by_date = posts_to_email
        .map(&:published_at_local_date)
        .each_with_object(Hash.new(0)) { |word, acc| acc[word] += 1 }

      Rails.logger.info("Posts to email: #{post_count_by_date}")
      if posts_to_email.empty?
        Rails.logger.info("Nothing to do")
        next 0
      end

      postmark_client, test_metadata = EmailJobHelper::get_client_and_metadata

      messages = []
      posts_to_email.each do |subscription_post|
        messages << SubscriptionPostMailer
          .with(
            subscription_post: subscription_post,
            test_metadata: test_metadata,
            server_timestamp: scheduled_for_str
          )
          .post_email
      end
      responses = postmark_client.deliver_messages(messages)

      sent, not_sent = posts_to_email
        .zip(messages, responses)
        .partition { |_, _, response| response[:error_code] == 0 }
      Rails.logger.info("Sent post messages: #{sent.length}")
      not_sent.each do |_, message, response|
        # Possible reasons for partial failure:
        # Rate limit exceeded
        # Not allowed to sent (ran out of credits)
        # Too many batch messages (?)

        Rails.logger.warn("Error sending email: #{message.metadata} - #{response}")
      end

      sent.each do |subscription_post, message, response|
        Rails.logger.info("Sent post email: #{message.metadata} - #{response}")
        PostmarkMessage.create!(
          message_id: response[:message_id],
          message_type: "sub_post",
          subscription_id: subscription_post.subscription_id,
          subscription_post_id: subscription_post.id
        )
        subscription_post.publish_status = "email_sent"
        subscription_post.save!
        ProductEvent.atomic_create!(
          product_user_id: user.product_user_id,
          event_type: "send post email",
          event_properties: {
            subscription_id: subscription_post.subscription_id,
            blog_url: subscription_post.subscription.blog.best_url
          }
        )
      end

      if not_sent.empty?
        # Schedule for a minute in the future so that the final email likely arrives last
        # Final item also depends on the email posts going out, so only sending it after a full success
        final_item_run_at = DateTime.now.utc.advance(minutes: 1)
        final_item_subscription_ids.each do |subscription_id|
          EmailFinalItemJob
            .set(wait_until: final_item_run_at)
            .perform_later(user_id, subscription_id, ScheduleHelper::utc_str(final_item_run_at))
        end
      end

      not_sent.length
    end

    raise "Messages not sent: #{not_sent_count}" if not_sent_count > 0
  end
end
