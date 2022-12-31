require 'net/http'
require 'uri'

class NotifySlackJob < ApplicationJob
  queue_as :default

  SIGNUP = "signup"

  def perform(webhook_name, text)
    case webhook_name
    when SIGNUP
      webhook_url = Rails.configuration.slack_signup_webhook
    else
      raise "Unknown webhook name: #{webhook_name}"
    end

    escaped_text = text
      .gsub("&", "&amp;")
      .gsub("<", "&lt;")
      .gsub(">", "&gt;")

    Net::HTTP.post(
      URI(webhook_url),
      { "text" => escaped_text }.to_json,
      { "Content-type" => "application/json" }
    )
  end
end


