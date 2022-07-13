class EmailInitialItemJob < ApplicationJob
  queue_as :default

  def perform(user_id, subscription_id, scheduled_for_str)
    Subscription.transaction do
      subscription = Subscription.find_by(id: subscription_id)
      unless subscription
        Rails.logger.info("Subscription not found")
        return
      end

      if subscription.initial_item_publish_status != "email_pending"
        Rails.logger.warn("Initial email already sent? Nothing to do")
        return
      end

      Rails.logger.info("Sending initial email")
      postmark_client, test_metadata = EmailJobHelper::get_client_and_metadata
      message = SubscriptionPostMailer
        .with(subscription: subscription, test_metadata: test_metadata, server_timestamp: scheduled_for_str)
        .initial_email
      response = postmark_client.deliver_message(message)

      raise "Error sending email: #{message.metadata} - #{response}" if response[:error_code] != 0

      Rails.logger.info("Initial email sent")
      subscription.initial_item_publish_status = "email_sent"
      subscription.save!
    end
  end
end
