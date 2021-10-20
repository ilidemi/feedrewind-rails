class LandingController < ApplicationController
  def index
    if cookies[:unfinished_blog]
      @blog = Blog.find_by(id: cookies[:unfinished_blog], user_id: nil)
    else
      @blog = nil
    end
  end

  def discard
    cookies.delete(:unfinished_blog)
    redirect_to action: "index"
  end
end
