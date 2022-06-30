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
    TestSingleton.transaction do
      TestSingleton.find("time_travel_command_id").update!(value: command_id.to_s)
      TestSingleton.find("time_travel_timestamp").update!(value: utc_now.to_s)
    end
  end
end
