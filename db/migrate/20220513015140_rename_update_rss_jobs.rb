class RenameUpdateRssJobs < ActiveRecord::Migration[6.1]
  def change
    reversible do |dir|
      dir.up do
        User.all.each do |user|
          execute "update delayed_jobs set handler = replace(handler, 'UpdateRssJobNew', 'UpdateRssJob') where handler like '%#{user.id}%'"
        end
      end
      dir.down do
        User.all.each do |user|
          execute "update delayed_jobs set handler = replace(handler, 'UpdateRssJob', 'UpdateRssJobNew') where handler like '%#{user.id}%'"
        end
      end
    end
  end
end
