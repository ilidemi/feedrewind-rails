require_relative "boot"
require_relative "../lib/middleware/log_request"
require_relative "../lib/middleware/log_static"

require "rails/all"
require "json"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module RssCatchupRails
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 6.1

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    config.active_job.queue_adapter = :delayed_job

    config.active_record.schema_format = :sql

    config.action_mailer.default_url_options = { host: 'feedrewind.com' }
    config.action_mailer.delivery_method = :postmark
    config.action_mailer.postmark_settings = { api_token: Rails.application.credentials.postmark_api_token! }

    Delayed::Worker.sleep_delay = 0.1
    Delayed::Worker.raise_signal_exceptions = :term

    Rails.autoloaders.main.ignore(Rails.root.join('app/lib'))

    config.middleware.insert_before(Rack::Sendfile, Rack::Deflater)
    config.middleware.insert_before(ActionDispatch::Static, LogStatic)
    config.middleware.use(LogRequest)

    config.after_initialize do
      # Make sure all shipped NPM dependencies have their license on about page

      dependencies_not_shipped = %w[@rails/webpacker webpack webpack-cli]

      File.open("package.json") do |package_json_file|
        package_json = JSON.parse(package_json_file.read)
        dependencies = package_json["dependencies"].keys

        File.open("app/views/misc/about.html.erb") do |about_file|
          about_str = about_file.read
          raise "Couldn't read about template" unless about_str

          dependencies.each do |dependency|
            next if dependencies_not_shipped.include?(dependency)

            unless about_str.include?("id=\"#{dependency}_license\"")
              raise "NPM dependency #{dependency} doesn't have a corresponding license on the about page"
            end
          end
        end
      end
    end

    def session_data(request)
      session_key = config.session_options[:key]
      request
        .cookie_jar
        .signed_or_encrypted[session_key] || {}
    end

    def session_id
      lambda do |request|
        begin
          value = session_data(request)["session_id"] || ""
          "S#{value[...8]}"
        rescue
          nil
        end
      end
    end

    def user_id
      lambda do |request|
        begin
          value = session_data(request)["user_id"] || ""
          "U#{value}"
        rescue
          nil
        end
      end
    end
  end
end
