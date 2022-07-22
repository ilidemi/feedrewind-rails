class PostmarkController < ApplicationController
  skip_before_action :verify_authenticity_token

  def report_bounce
    webhook_secret = request.headers["webhook-secret"]
    unless webhook_secret == Rails.application.credentials.postmark_webhook_secret!
      raise "Webhook secret not matching: #{webhook_secret}"
    end

    bounce_str = request.body.read
    bounce_json = JSON.parse(bounce_str)
    bounce = Postmark::HashHelper.to_ruby(bounce_json)

    PostmarkBounce.transaction do
      if PostmarkBounce.exists?(bounce[:id])
        Rails.logger.info("Bounce already seen: #{bounce[:id]}")
      else
        Rails.logger.info("New bounce: #{bounce[:id]}")
        PostmarkBounce.create!(
          id: bounce[:id],
          bounce_type: bounce[:type],
          message_id: bounce[:message_id],
          payload: bounce
        )
        ProcessPostmarkBounceJob.perform_later(bounce[:id])
      end
    end
  end
end
