class UsersController < ApplicationController
  def new
    @user = User.new
  end

  def create
    user_params = params.require(:user).permit(:email, :password, :password_confirmation)
    @user = User.new(user_params)
    if @user.save
      session[:user_id] = @user.id

      if cookies[:blog_to_add]
        blog = Blog.find_by(id: cookies[:blog_to_add], user_id: nil)
        cookies.delete(:blog_to_add)
      else
        blog = nil
      end

      if blog
        blog.user_id = @user.id
        blog.save
        redirect_to BlogsHelper.setup_path(blog), notice: "Thank you for signing up!"
      else
        redirect_to blogs_path, notice: "Thank you for signing up!"
      end
    else
      render :new
    end
  end
end
