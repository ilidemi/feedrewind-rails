class RssController < ApplicationController
  def show
    @blog = Blog.find_by(name: params[:name])
    @rss = CurrentRss.find_by(blog_id: @blog.id)
    render body: @rss.body, content_type: 'application/xml'
  end
end
