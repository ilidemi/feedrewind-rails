require 'net/http'
require 'uri'

class NotifySlackJob < ApplicationJob
  queue_as :default

  def perform(text)
    webhook_url = Rails.configuration.slack_webhook

    Net::HTTP.post(
      URI(webhook_url),
      { "text" => text }.to_json,
      { "Content-type" => "application/json" }
    )
  end

  def NotifySlackJob::escape(text)
    text
      .gsub("&", "&amp;")
      .gsub("<", "&lt;")
      .gsub(">", "&gt;")
  end
end


