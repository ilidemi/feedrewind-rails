class EmailFinalItemJob < ApplicationJob
  queue_as :default

  def perform(user_id, subscription_id, scheduled_for_str)
    Subscription.transaction do
      subscription = Subscription.find_by(id: subscription_id)
      unless subscription
        Rails.logger.info("Subscription not found")
        return
      end

      if subscription.final_item_publish_status != "email_pending"
        Rails.logger.warn("Final email already sent? Nothing to do")
        return
      end

      Rails.logger.info("Sending final email")
      postmark_client, test_metadata = EmailJobHelper::get_client_and_metadata
      message = SubscriptionPostMailer
        .with(subscription: subscription, test_metadata: test_metadata, server_timestamp: scheduled_for_str)
        .final_email
      response = postmark_client.deliver_message(message)

      raise "Error sending email: #{message.metadata} - #{response}" if response[:error_code] != 0

      Rails.logger.info("Final email sent")
      subscription.final_item_publish_status = "email_sent"
      subscription.save!
    end
  end
end
