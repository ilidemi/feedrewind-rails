class DiscoveryChannel < ApplicationCable::Channel
  def subscribed
    stream_from "discovery_#{params[:blog_id]}"
  end
end
