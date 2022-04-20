class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  def self.schedule_for_tomorrow(*args)
    next_run = ScheduleHelper::now.advance_till_midnight.date
    self
      .set(wait_until: next_run)
      .perform_later(*args)
  end
end
