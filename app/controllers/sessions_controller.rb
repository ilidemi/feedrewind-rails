class SessionsController < ApplicationController
  def new
  end

  def create
    user = User.find_by_email(params[:email])
    if user && user.authenticate(params[:password])
      session[:user_id] = user.id

      if cookies[:unfinished_blog]
        blog = Blog.find_by(id: cookies[:unfinished_blog], user_id: nil)
        cookies.delete(:unfinished_blog)
      else
        blog = nil
      end

      if blog
        blog.user_id = user.id
        blog.save!
        redirect_to BlogsHelper.setup_path(blog), notice: "Logged in!"
      else
        redirect_to blogs_path, notice: "Logged in!"
      end
    else
      flash.now.alert = "Email or password is invalid"
      render "new"
    end
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "Logged out!"
  end
end
