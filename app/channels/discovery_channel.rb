class DiscoveryChannel < ApplicationCable::Channel
  def subscribed
    stream_from "discovery_channel"
  end
end
