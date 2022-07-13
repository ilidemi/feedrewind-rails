class RenameUpdateRssJob < ActiveRecord::Migration[6.1]
  def up
    execute "update delayed_jobs set handler = replace(handler, 'class: UpdateRssJob', 'class: PublishPostsJob') where handler like '%class: UpdateRssJob%'"
  end

  def down
    execute "update delayed_jobs set handler = replace(handler, 'class: PublishPostsJob', 'class: UpdateRssJob') where handler like '%class: PublishPostsJob%'"
  end
end
