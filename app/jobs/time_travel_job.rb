class TimeTravelJob < ApplicationJob
  queue_as :default

  def perform(command_id, action, timestamp)
    raise "No time travel in production!" unless Rails.env.development? || Rails.env.test?

    case action
    when "travel_to"
      TimeTravelHelper::travel_to(timestamp)
    when "travel_back"
      TimeTravelHelper::travel_back
    else
      raise "Unknown action: #{action}"
    end

    utc_now = DateTime.now.utc
    Rails.logger.info("Current time: #{utc_now}")
    LastTimeTravel
      .find(0)
      .update!(last_command_id: command_id, timestamp: utc_now)
  end
end
