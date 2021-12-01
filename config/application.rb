require_relative "boot"

require "rails/all"

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

    Delayed::Worker.sleep_delay = 0.1
    Delayed::Worker.raise_signal_exceptions = :term

    Rails.autoloaders.main.ignore(Rails.root.join('app/lib'))

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
          "U#{value[...8]}"
        rescue
          nil
        end
      end
    end
  end
end
