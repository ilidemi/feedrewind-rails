class EmailFinalItemJob < ApplicationJob
  queue_as :default

  def perform(user_id, subscription_id, scheduled_for_str)
    Subscription.transaction do
      unless User.exists?(user_id)
        Rails.logger.info("User #{user_id} not found")
        return
      end

      if PostmarkBouncedUser.exists?(user_id)
        Rails.logger.info("User #{user_id} marked as bounced, not sending anything")
        return
      end

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

      # Postmark duplicates keys as symbols and strings for some reason
      filtered_response = response.filter { |key, _| key.is_a?(Symbol) }

      raise "Error sending email: #{message.metadata} - #{filtered_response}" if response[:error_code] != 0

      Rails.logger.info("Final email sent: #{message.metadata} - #{filtered_response}")
      PostmarkMessage.create!(
        message_id: filtered_response[:message_id],
        message_type: "sub_final",
        subscription_id: subscription_id,
        subscription_post_id: nil
      )
      subscription.final_item_publish_status = "email_sent"
      subscription.save!
    end
  end
end
