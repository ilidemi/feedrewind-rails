class CreateResetFailedBlogsJob < ActiveRecord::Migration[6.1]
  def up
    ResetFailedBlogsJob.schedule_for_tomorrow(true)
  end

  def down
    Delayed::Job.all.each do |job|
      if job.queue == "reset_failed_blogs"
        job.destroy!
      end
    end
  end
end
