class LogStatic
  def initialize(app)
    @app = app
  end

  def call(env)
    res = @app.call(env)

    if res[2].is_a?(Rack::Files::Iterator) ||
      res[2].is_a?(Rack::Files::BaseIterator) ||
      env["REQUEST_PATH"].start_with?("/packs") ||
      env["REQUEST_PATH"].start_with?("/assets")

      ProductEvent::dummy_create!(
        user_ip: env["REMOTE_ADDR"],
        user_agent: env["HTTP_USER_AGENT"],
        allow_bots: false,
        event_type: "static asset",
        event_properties: {
          path: env["REQUEST_PATH"]
        }
      )
    end

    res
  end
end