require "addressable/uri"
require "json"
require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  Capybara.run_server = false
  Capybara.default_max_wait_time = 0.5
  Selenium::WebDriver.logger.ignore(:browser_options)
  driven_by :selenium, using: :chrome, screen_size: [1400, 1400] do |options|
    options.add_argument("--log-level=3")
  end

  def visit_dev(path)
    visit "http://localhost:3000/#{path}"
  end

  def visit_admin(path)
    visit "http://localhost:3000/test/#{path}"
  end

  def visit_admin_sql(query)
    escaped_query = Addressable::URI.escape(query)
    visit_admin("execute_sql?query=#{escaped_query}")
    JSON.parse(page.document.text)
  end
end
