require 'securerandom'

class ApplicationController < ActionController::Base
  before_action :redirect_subdomain
  before_action :log_visit
  rescue_from ActionController::InvalidAuthenticityToken, with: :log_error_as_info

  self.log_warning_on_csrf_failure = false

  def route_not_found
    ProductEvent::dummy_create!(
      user_ip: request.ip,
      user_agent: request.user_agent,
      allow_bots: false,
      event_type: "404",
      event_properties: {
        path: request.path,
        method: request.method,
        referer: request.referer
      }
    )
    render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
  end

  private

  def redirect_subdomain
    if request.host == 'www.feedrewind.com'
      redirect_to 'https://feedrewind.com' + request.fullpath, :status => 301
    end
  end

  def log_visit
    referer = ProductEventHelper::collapse_referer(request.referer)
    ProductEvent::dummy_create!(
      user_ip: request.ip,
      user_agent: request.user_agent,
      allow_bots: true,
      event_type: "visit",
      event_properties: {
        action: "#{params[:controller]}/#{params[:action]}",
        referer: referer
      }
    )
  end

  def current_user
    if session[:auth_token]
      @current_user ||= User.find_by(auth_token: session[:auth_token])
    end

    if @current_user
      @product_user_id = @current_user.product_user_id
    elsif session[:product_user_id]
      @product_user_id = session[:product_user_id]
    else
      @product_user_id = SecureRandom.uuid
      session[:product_user_id] = @product_user_id
    end

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
    raise ActionController::RoutingError.new('Not Found') if current_user.nil? || !is_admin(current_user.id)
  end

  def fill_current_user
    current_user
    nil
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
