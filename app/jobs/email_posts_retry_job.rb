require 'postmark'
require 'tzinfo'

class EmailPostsRetryJob < ApplicationJob
  queue_as :default

  def perform(user_id, subscription_post_ids)
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

    not_sent_count = SubscriptionPost.transaction do
      posts_to_email = SubscriptionPost
        .where(id: subscription_post_ids)
        .where(email_status: "pending") # some might've succeeded on an earlier retry
        .to_a

      Rails.logger.info("Posts to retry email: #{posts_to_email.length}")

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
      Rails.logger.info("Sent retry messages: #{sent.length}")
      not_sent.each do |_, message, response|
        # Possible reasons for partial failure:
        # Rate limit exceeded
        # Not allowed to sent (ran out of credits)
        # Too many batch messages (?)

        Rails.logger.warn("Error sending retry email: #{message.metadata} - #{response}")
      end

      sent.each do |subscription_post, _, _|
        subscription_post.email_status = "sent"
        subscription_post.save!
      end

      not_sent.length
    end

    raise "Email retry failed for #{not_sent_count} messages" unless not_sent_count == 0
  end
end
