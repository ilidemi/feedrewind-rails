require 'browser'
require 'net/http'
require 'uri'

class DispatchAmplitudeJob < ApplicationJob
  queue_as :default

  def perform(is_manual = false)
    amplitude_uri = URI("https://api.amplitude.com/2/httpapi")
    api_key = Rails.configuration.amplitude_api_key

    dispatched_count = 0
    bot_skipped_count = 0
    bot_counts = {}
    failed_count = 0
    ProductEvent.where(dispatched_at: nil).order(:id).each do |product_event|
      if product_event.user_agent
        browser = Browser.new(product_event.user_agent)
        if browser.bot?
          bot_skipped_count += 1
          bot_name = browser.bot.name
          bot_counts[bot_name] = 0 unless bot_counts.include?(bot_name)
          bot_counts[bot_name] += 1
          next
        end
      else
        browser = nil
      end

      event = {
        "user_id" => product_event.product_user_id,
        "event_type" => product_event.event_type,
        "time" => product_event.created_at.to_datetime.strftime('%Q'),
        "event_properties" => product_event.event_properties,
        "user_properties" => product_event.user_properties,
        "platform" => browser&.name,
        "os_name" => browser&.platform&.name,
        "os_version" => browser&.platform&.version,
        "device_manufacturer" => browser&.device&.id&.to_s,
        "device_model" => browser&.device&.name,
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

  def NotifySlackJob::escape(text)
    text
      .gsub("&", "&amp;")
      .gsub("<", "&lt;")
      .gsub(">", "&gt;")
  end
end



