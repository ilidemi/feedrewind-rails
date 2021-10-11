class RssController < ApplicationController
  def show
    @blog = Blog.find(params[:id])
    @rss = CurrentRss.find_by(blog_id: @blog.id)
    render body: @rss.body, content_type: 'application/xml'
  end
end
