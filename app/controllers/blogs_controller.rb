class BlogsController < ApplicationController
  def unsupported
    fill_current_user

    @blog = Blog.find(params[:id])
    unless %w[crawl_failed crawl_looks_wrong].include?(@blog.status)
      return render nothing: true, status: :bad_request
    end

    render
  end
end
