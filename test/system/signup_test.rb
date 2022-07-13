require "application_system_test_case"

class SignupTest < ApplicationSystemTestCase
  SignupData = Struct.new(:email, :timezone, :set_delivery_page)
  signup_rss_data = [
    # @formatter:off
    SignupData.new("test_nz@test.com",  "Pacific/Auckland",    :settings),
    SignupData.new("test_pst@test.com", "America/Los_Angeles", :settings),
    SignupData.new("test_nz@test.com",  "Pacific/Auckland",    :schedule),
    SignupData.new("test_pst@test.com", "America/Los_Angeles", :schedule)
    # @formatter:on
  ]

  signup_email_data = [
    # @formatter:off
    SignupData.new("test_email_nz@feedrewind.com",  "Pacific/Auckland",    :settings),
    SignupData.new("test_email_pst@feedrewind.com", "America/Los_Angeles", :settings),
    SignupData.new("test_email_nz@feedrewind.com",  "Pacific/Auckland",    :schedule),
    SignupData.new("test_email_pst@feedrewind.com", "America/Los_Angeles", :schedule)
  # @formatter:on
  ]

  signup_rss_data.each do |data|
    test "Timezone #{data.timezone}, sign up and choose rss delivery in #{data.set_delivery_page}" do
      visit_admin "destroy_user?email=#{data.email}"
      assert_includes(%w[OK NotFound], page.document.text)

      page.driver.browser.execute_cdp(
        "Emulation.setTimezoneOverride",
        timezoneId: data.timezone
      )

      today_utc = DateTime.new(2022, 6, 1)
      case data.timezone
      when "America/Los_Angeles"
        today_local = today_utc.advance(hours: 7)
      when "Pacific/Auckland"
        today_local = today_utc.advance(hours: -12)
      else
        raise "Unknown timezone: #{data.timezone}"
      end
      signup_timestamp = today_local.advance(hours: 1)
      rss_publish_timestamp = today_local.advance(hours: 2)

      visit_admin "travel_to_v2?timestamp=#{signup_timestamp}"
      assert_equal signup_timestamp, page.document.text

      # Create user
      visit_dev "signup"
      fill_in "email", with: data.email
      fill_in "new-password", with: "tz123456"
      click_button "Sign up"

      # Assert timezone
      visit_dev "settings"
      assert_selector "option[value='#{data.timezone}'][selected='selected']"

      if data.set_delivery_page == :settings
        # Set delivery channel
        choose "delivery_rss"
        assert_selector "#delivery_channel_save_spinner", visible: :hidden
      end

      # Add a subscription
      visit_dev "subscriptions/add"
      fill_in "start_url", with: "https://ilidemi.github.io/dummy-blogs/1a/rss.xml"
      click_button "Go"

      while page.has_css?("#progress_count")
        sleep(0.1)
      end

      if page.has_css?("#confirm_section")
        click_button "Continue"
      end

      click_button "wed_add"

      case data.set_delivery_page
      when :settings
        assert_no_selector "#delivery_channel_picker"
      when :schedule
        # Set delivery channel
        choose "delivery_rss"
      else
        raise "Unknown set delivery page: #{data.set_delivery_page}"
      end

      click_button "Continue"
      assert_selector "#arrival_msg"

      subscription_id = /[0-9]+/.match(page.current_path)[0]
      subscription_path = "subscriptions/#{subscription_id}"

      # Assert published count
      visit_admin "travel_to_v2?timestamp=#{rss_publish_timestamp}"
      assert_equal rss_publish_timestamp, page.document.text
      visit_admin "wait_for_publish_posts_job"
      assert_equal "OK", page.document.text
      visit_dev subscription_path
      published_count = /^[0-9]+/.match(page.find("#published_count").text)[0].to_i
      assert_equal 1, published_count

      # Cleanup
      visit_admin "travel_back_v2"
      assert_in_delta DateTime.now.utc, DateTime.parse(page.document.text), 60
      visit_admin "reschedule_user_job"
      assert_equal "OK", page.document.text
    end
  end

  signup_email_data.each do |data|
    test "Timezone #{data.timezone}, sign up and choose email delivery in #{data.set_delivery_page}" do
      visit_admin "destroy_user?email=#{data.email}"
      assert_includes(%w[OK NotFound], page.document.text)

      page.driver.browser.execute_cdp(
        "Emulation.setTimezoneOverride",
        timezoneId: data.timezone
      )

      today_utc = DateTime.new(2022, 6, 1)
      case data.timezone
      when "America/Los_Angeles"
        today_local = today_utc.advance(hours: 7)
      when "Pacific/Auckland"
        today_local = today_utc.advance(hours: -12)
      else
        raise "Unknown timezone: #{data.timezone}"
      end
      signup_timestamp = today_local.advance(hours: 1)
      email_timestamp = today_local.advance(hours: 5)

      visit_admin "travel_to_v2?timestamp=#{signup_timestamp}"
      assert_equal signup_timestamp, page.document.text

      email_metadata = RandomId::generate_random_bigint
      visit_admin "set_email_metadata?value=#{email_metadata}"
      assert_equal "OK", page.document.text

      # Create user
      visit_dev "signup"
      fill_in "email", with: data.email
      fill_in "new-password", with: "tz123456"
      click_button "Sign up"

      # Assert timezone
      visit_dev "settings"
      assert_selector "option[value='#{data.timezone}'][selected='selected']"

      if data.set_delivery_page == :settings
        # Set delivery channel
        choose "delivery_email"
        assert_selector "#delivery_channel_save_spinner", visible: :hidden
      end

      # Add a subscription
      visit_dev "subscriptions/add"
      fill_in "start_url", with: "https://ilidemi.github.io/dummy-blogs/1a/rss.xml"
      click_button "Go"

      while page.has_css?("#progress_count")
        sleep(0.1)
      end

      if page.has_css?("#confirm_section")
        click_button "Continue"
      end

      click_button "wed_add"

      case data.set_delivery_page
      when :settings
        assert_no_selector "#delivery_channel_picker"
      when :schedule
        # Set delivery channel
        choose "delivery_email"
      else
        raise "Unknown set delivery page: #{data.set_delivery_page}"
      end

      click_button "Continue"
      assert_selector "#arrival_msg"

      # Assert published count
      visit_admin "travel_to_v2?timestamp=#{email_timestamp}"
      assert_equal email_timestamp, page.document.text
      visit_admin "wait_for_publish_posts_job"
      assert_equal "OK", page.document.text
      visit_admin "assert_email_count_with_metadata?value=#{email_metadata}&count=2&last_timestamp=#{ScheduleHelper::utc_str(email_timestamp)}&last_tag=subscription_post"
      assert_equal "OK", page.document.text

      # Cleanup
      visit_admin "travel_back_v2"
      assert_in_delta DateTime.now.utc, DateTime.parse(page.document.text), 60
      visit_admin "reschedule_user_job"
      assert_equal "OK", page.document.text
    end
  end
end
