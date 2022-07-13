class AddScheduledForStr < ActiveRecord::Migration[6.1]
  def up
    execute "delete from delayed_jobs where handler like E'%class: PublishPostsJob\\n%'"
    User.all.each do |user|
      next unless user.user_settings.delivery_channel

      PublishPostsJob.initial_schedule(user)
    end
  end
end
