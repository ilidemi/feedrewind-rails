class SchedulePollPostmarkBouncesJob < ActiveRecord::Migration[6.1]
  def up
    postmark_client, _ = EmailJobHelper::get_client_and_metadata
    initial_bounces = postmark_client.get_bounces(count: 100, offset: 0)
    initial_bounces.each do |bounce|
      PostmarkBounce.create!(
        id: bounce[:id],
        bounce_type: bounce[:type],
        message_id: bounce[:message_id],
        payload: bounce # partial
      )
    end

    PollPostmarkBouncesJob.perform_later
  end
end
