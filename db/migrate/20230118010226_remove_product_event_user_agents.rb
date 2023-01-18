require 'browser'

class RemoveProductEventUserAgents < ActiveRecord::Migration[6.1]
  def up
    add_column :product_events, :browser, :text
    add_column :product_events, :os_name, :text
    add_column :product_events, :os_version, :text
    add_column :product_events, :bot_name, :text

    ProductEvent.all.each do |product_event|
      next unless product_event.user_agent

      browser = Browser.new(product_event.user_agent)
      if browser.bot?
        product_event.browser = "Crawler"
        product_event.os_name = "Crawler"
        product_event.os_version = "Crawler"
        product_event.bot_name = browser.bot.name
      else
        product_event.browser = browser.name
        product_event.os_name = browser.platform&.name
        product_event.os_version = browser.platform&.version
      end
      product_event.save!
    end

    remove_column :product_events, :user_agent
  end
end
