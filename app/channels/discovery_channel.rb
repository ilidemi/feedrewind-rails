class DiscoveryChannel < ApplicationCable::Channel
  def subscribed
    stream_from "discovery_#{params[:blog_id]}"
  end

  def after_subscribe
    blog = Blog.find(params[:blog_id])
    if blog.status != "crawl_in_progress"
      # Safeguard from race condition with the job and client UI hanging
      ActionCable.server.broadcast("discovery_#{params[:blog_id]}", { done: true })
    end

    sleep(1)

    blog = Blog.find(params[:blog_id])
    if blog.status != "crawl_in_progress"
      # Safeguard from race condition with the job and client UI hanging
      ActionCable.server.broadcast("discovery_#{params[:blog_id]}", { done: true })
    end
  end
end
