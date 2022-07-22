class RetryBouncedEmailJob < ApplicationJob
  def perform(message_id)
    postmark_message = PostmarkMessage.find(message_id)
    postmark_client, test_metadata = EmailJobHelper::get_client_and_metadata
    scheduled_for_str = ScheduleHelper::utc_str(DateTime.now.utc)
    Rails.logger.info("Retrying message: #{postmark_message}")

    case postmark_message.message_type
    when "sub_initial"
      subscription = Subscription.find(postmark_message.subscription_id)
      message = SubscriptionPostMailer
        .with(subscription: subscription, test_metadata: test_metadata, server_timestamp: scheduled_for_str)
        .initial_email
    when "sub_final"
      subscription = Subscription.find(postmark_message.subscription_id)
      message = SubscriptionPostMailer
        .with(subscription: subscription, test_metadata: test_metadata, server_timestamp: scheduled_for_str)
        .final_email
    when "sub_post"
      subscription_post = SubscriptionPost.find(postmark_message.subscription_post_id)
      message = SubscriptionPostMailer
        .with(
          subscription_post: subscription_post,
          test_metadata: test_metadata,
          server_timestamp: scheduled_for_str
        )
        .post_email
    else
      raise "Unexpected message type: #{postmark_message.message_type}"
    end

    response = postmark_client.deliver_message(message)

    # Postmark duplicates keys as symbols and strings for some reason
    filtered_response = response.filter { |key, _| key.is_a?(Symbol) }

    raise "Error sending email: #{message.metadata} - #{filtered_response}" if response[:error_code] != 0

    Rails.logger.info("Sent email: #{message.metadata} - #{filtered_response}")
    PostmarkMessage.create!(
      message_id: response[:message_id],
      message_type: postmark_message.message_type,
      subscription_id: postmark_message.subscription_id,
      subscription_post_id: postmark_message.subscription_post_id
    )
  end
end
