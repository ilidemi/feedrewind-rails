class ApplicationController < ActionController::Base
  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  helper_method :current_user

  def authorize
    redirect_to login_path, alert: "Not authorized" if current_user.nil?
  end

  def authorize_admin
    unless Rails.configuration.admin_user_ids.include?(current_user.id)
      raise ActionController::RoutingError.new('Not Found')
    end
  end

  def fill_current_user
    current_user
  end
end
