class UnscheduleEmailPostsJob < ActiveRecord::Migration[6.1]
  def up
    execute <<-SQL
      delete from delayed_jobs
      where handler like concat(E'%class: EmailPostsJob\n%')
    SQL
  end
end
