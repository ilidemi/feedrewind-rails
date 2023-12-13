require 'browser'
require 'net/http'
require 'uri'

class DispatchAmplitudeJob < ApplicationJob
  queue_as :default

  def perform(is_manual = false)
    amplitude_uri = URI("https://api.amplitude.com/2/httpapi")
    api_key = Rails.configuration.amplitude_api_key

    events_to_dispatch = ProductEvent.where(dispatched_at: nil).order(:id)
    Rails.logger.info("Dispatching #{events_to_dispatch.length} events")

    dispatched_count = 0
    bot_skipped_count = 0
    bot_counts = {}
    failed_count = 0
    events_to_dispatch.each_with_index do |product_event, i|
      if i != 0 && i % 100 == 0
        Rails.logger.info("Event #{i}")
      end

      if product_event.bot_name &&
        product_event.user_properties &&
        !product_event.user_properties["allow_bots"]

        bot_skipped_count += 1
        bot_name = product_event.bot_name
        bot_counts[bot_name] = 0 unless bot_counts.include?(bot_name)
        bot_counts[bot_name] += 1
        product_event.dispatched_at = DateTime.now.utc
        product_event.save!

        next
      end

      event = {
        "user_id" => product_event.product_user_id,
        "event_type" => product_event.event_type,
        "time" => product_event.created_at.to_datetime.strftime('%Q'),
        "event_properties" => product_event.event_properties,
        "user_properties" => product_event.user_properties,
        "platform" => product_event.browser,
        "os_name" => product_event.os_name,
        "os_version" => product_event.os_version,
        "ip" => product_event.user_ip,
        "event_id" => product_event.id,
        "insert_id" => product_event.id.to_s
      }

      response = Net::HTTP.post(
        amplitude_uri,
        {
          "api_key" => api_key,
          "events" => [event]
        }.to_json,
        {
          "Content-type" => "application/json",
          "Accept" => "*/*"
        }
      )

      if response.code == "200"
        product_event.dispatched_at = DateTime.now.utc
        product_event.save!
        dispatched_count += 1
      else
        Rails.logger.warn("Amplitude post failed for event #{product_event.id}: #{response.code} #{response.message} #{response.body}")
        failed_count += 1
      end
    end

    Rails.logger.info("Dispatched #{dispatched_count} events, skipped #{bot_skipped_count} bot events (#{bot_counts}), failed #{failed_count} events")

    unless is_manual
      next_run = DateTime.now.utc.advance(hours: 1).beginning_of_hour
      DispatchAmplitudeJob.set(wait_until: next_run).perform_later
    end
  end
end



