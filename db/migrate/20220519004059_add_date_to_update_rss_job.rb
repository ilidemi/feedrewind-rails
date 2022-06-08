class AddDateToUpdateRssJob < ActiveRecord::Migration[6.1]
  def up
    execute <<-SQL
      update delayed_jobs
      set handler = replace(handler, '  executions: 0', concat('  - ', to_char(run_at, 'YYYY-MM-DD'), E'\n  executions: 0'))
      where handler like '%class: UpdateRssJob%'
    SQL
  end

  def down
    execute <<-SQL
      update delayed_jobs
      set handler = regexp_replace(handler, '  - [0-9-]+\n  executions: 0', '  executions: 0')
      where handler like '%class: UpdateRssJob%'
    SQL
  end
end
