class PollPostmarkBouncesJob < ApplicationJob
  queue_as :default

  def perform
    postmark_client, _ = EmailJobHelper::get_client_and_metadata

    bounces = postmark_client.get_bounces(count: 100, offset: 0)
    Rails.logger.info("Queried #{bounces.length} bounces")

    full_bounces = []
    bounces.each do |bounce|
      next if PostmarkBounce.exists?(bounce[:id])
      full_bounce = postmark_client.get_bounce(bounce[:id])
      full_bounces << full_bounce
    end
    Rails.logger.info("New bounces: #{full_bounces.length}")

    PostmarkBounce.transaction do
      full_bounces.each do |full_bounce|
        next if PostmarkBounce.exists?(full_bounce[:id])

        Rails.logger.warn("Inserting Postmark bounce: #{full_bounce.filter { |key, _| key != :content}}")
        PostmarkBounce.create!(
          id: full_bounce[:id],
          bounce_type: full_bounce[:type],
          message_id: full_bounce[:message_id],
          payload: full_bounce
        )

        ProcessPostmarkBounceJob.perform_later(full_bounce[:id])
      end

      PollPostmarkBouncesJob.set(wait: 1.hours).perform_later
    end
  end
end

