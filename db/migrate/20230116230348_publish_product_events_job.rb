class PublishProductEventsJob < ActiveRecord::Migration[6.1]
  def up
    DispatchAmplitudeJob.perform_later
  end

  def down
    execute <<-SQL
      delete from delayed_jobs where handler like '%class: DispatchAmplitudeJob%'
    SQL
  end
end
