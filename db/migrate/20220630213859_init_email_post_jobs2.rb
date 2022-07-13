class InitEmailPostJobs2 < ActiveRecord::Migration[6.1]
  def up
    # It is not periodic anymore

    # User.all.each do |user|
    #   begin
    #     UserJobHelper.get_next_scheduled_date(EmailPostsJob, user.id)
    #   rescue
    #     EmailPostsJob.initial_schedule(user)
    #   end
    # end
  end

  def down
    execute "delete from delayed_jobs where handler like E'%class: EmailPostsJob\\n%'"
  end
end
