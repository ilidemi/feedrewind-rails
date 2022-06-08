require 'tzinfo'

class FixJobDates2 < ActiveRecord::Migration[6.1]
  def up
    User.all.each do |user|
      execute "delete from delayed_jobs where handler like '%UpdateRssJob%' and handler like '%#{user.id}%'"
      UpdateRssJob.initial_schedule(user)
    end
  end

  def down
  end
end
