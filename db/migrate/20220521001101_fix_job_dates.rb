class FixJobDates < ActiveRecord::Migration[6.1]
  def up
    execute <<-SQL
      update delayed_jobs
      set handler = regexp_replace(handler, E'(  - )([0-9-]+)(\nexecutions: 0)', '\1"\2"\3')
      where handler like '%class: UpdateRssJob%'
    SQL
  end
end
