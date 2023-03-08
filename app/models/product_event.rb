require 'browser'
require 'securerandom'

class ProductEvent < ApplicationRecord
  def ProductEvent::from_request!(
    request, product_user_id:, event_type:, event_properties: nil, user_properties: nil
  )
    user_platform = ProductEvent::resolve_user_agent(request.user_agent)
    now_utc = DateTime.now.utc
    ProductEvent.insert!(
      product_user_id: product_user_id,
      event_type: event_type,
      event_properties: event_properties,
      user_properties: user_properties,
      user_ip: ProductEvent::anonymize_user_ip(request.ip),
      browser: user_platform.browser,
      os_name: user_platform.os_name,
      os_version: user_platform.os_version,
      bot_name: user_platform.bot_name,
      created_at: now_utc,
      updated_at: now_utc
    )
  end

  def ProductEvent::atomic_create!(attributes)
    now_utc = DateTime.now.utc
    ProductEvent.insert!(
      created_at: now_utc,
      updated_at: now_utc,
      **attributes
    )
  end

  def ProductEvent::dummy_create!(
    user_ip:, user_agent:, allow_bots:, event_type:, event_properties: nil
  )
    user_platform = ProductEvent::resolve_user_agent(user_agent)
    now_utc = DateTime.now.utc
    ProductEvent.insert!(
      product_user_id: "dummy-#{SecureRandom.uuid}",
      event_type: event_type,
      event_properties: event_properties,
      user_properties: {
        is_dummy: true,
        bot_is_allowed: allow_bots
      },
      user_ip: ProductEvent::anonymize_user_ip(user_ip),
      browser: user_platform.browser,
      os_name: user_platform.os_name,
      os_version: user_platform.os_version,
      bot_name: user_platform.bot_name,
      created_at: now_utc,
      updated_at: now_utc
    )
  end

  private

  def ProductEvent::anonymize_user_ip(user_ip)
    user_ip.gsub(/\.\d+\.\d+$/, ".0.1")
  end

  UserPlatform = Struct.new(:browser, :os_name, :os_version, :bot_name, keyword_init: true)

  def ProductEvent::resolve_user_agent(user_agent)
    browser = Browser.new(user_agent)
    if browser.bot?
      UserPlatform.new(
        browser: "Crawler",
        os_name: "Crawler",
        os_version: "Crawler",
        bot_name: browser.bot.name
      )
    else
      UserPlatform.new(
        browser: browser.name,
        os_name: browser.platform&.name,
        os_version: browser.platform&.version,
        bot_name: nil
      )
    end
  end
end

