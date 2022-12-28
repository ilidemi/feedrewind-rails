class ApplicationController < ActionController::Base
  before_action :redirect_subdomain
  rescue_from ActionController::InvalidAuthenticityToken, with: :log_error_as_info

  self.log_warning_on_csrf_failure = false

  def route_not_found
    render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
  end

  private

  def redirect_subdomain
    if request.host == 'www.feedrewind.com'
      redirect_to 'https://feedrewind.com' + request.fullpath, :status => 301
    end
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
    if @current_user
      @current_user_has_bounced = PostmarkBouncedUser.exists?(@current_user.id)
    else
      @current_user_has_bounced = false
    end
    @current_user
  end

  helper_method :current_user

  def authorize
    redirect_to SessionsHelper::login_path_with_redirect(request) if current_user.nil?
  end

  def is_admin(user_id)
    return true if Rails.env.development? || Rails.env.test?
    return true if Rails.configuration.admin_user_ids.include?(user_id)
    false
  end

  def authorize_admin
    raise ActionController::RoutingError.new('Not Found') unless is_admin(current_user.id)
  end

  def fill_current_user
    current_user
  end

  private

  def log_error_as_info(e)
    Rails.logger.info do
      message = +"#{e.class} (#{e.message}):\n"
      message << e.annotated_source_code.to_s if e.respond_to?(:annotated_source_code)
      message << "  " << e.backtrace.join("\n  ")
      "#{message}\n\n"
    end
  end
end
