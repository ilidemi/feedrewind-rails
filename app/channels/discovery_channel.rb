require_relative 'application_cable/application_cable_hack'

class DiscoveryChannel < ApplicationCable::Channel
  def subscribed
    stream_from "discovery_#{params[:blog_id]}"
  end

  def after_confirmation_sent
    transmit_status
    10.times do
      sleep(0.1)
      transmit_status
    end
  end

  private

  def transmit_status
    payload = Blog::crawl_progress_json(params[:blog_id])
    payload["force_push"] = true
    transmit(payload)
  end
end
