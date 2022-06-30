class InitEmailPostJobs < ActiveRecord::Migration[6.1]
  def up
    # Don't migrate for now, for the sake of manual testing

    # User.all.each do |user|
    #   EmailPostsJob.initial_schedule(user)
    # end
  end

  def down
    # execute "delete from delayed_jobs where handler like E'%class: EmailPostsJob\\n%'"
  end
end
