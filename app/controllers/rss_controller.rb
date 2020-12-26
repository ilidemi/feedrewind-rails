class RssController < ApplicationController
  def show
    @user = User.find(params[:user_id])
    @blog = @user.blogs.find_by(name: params[:name])
    @rss = CurrentRss.find_by(blog_id: @blog.id)
    render body: @rss.body, content_type: 'application/xml'
  end
end
