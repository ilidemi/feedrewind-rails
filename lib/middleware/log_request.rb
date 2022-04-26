class LogRequest
  def initialize(app)
    @app = app
  end

  def call(env)
    Rails.logger.info("User agent: #{env["HTTP_USER_AGENT"]}")
    Rails.logger.info("Referer: #{env["HTTP_REFERER"]}")
    @app.call(env)
  end
end