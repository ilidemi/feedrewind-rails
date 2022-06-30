require "application_system_test_case"

class TimezoneSignupTest < ApplicationSystemTestCase
  SignupData = Struct.new(:email, :timezone, :email_delivery)
  signup_data = [
    SignupData.new("test_nz@test.com", "Pacific/Auckland", false),
    SignupData.new("test_pst@test.com", "America/Los_Angeles", false),
    SignupData.new("ilidemi@feedrewind.com", "America/Los_Angeles", true)
  ]

  signup_data.each do |data|
    test "Timezone #{data.timezone}, email delivery #{data.email_delivery} sign up" do
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
      visit_admin "travel_to_v2?timestamp=#{signup_timestamp}"
      assert_equal signup_timestamp, page.document.text

      # Create user
      visit_dev "signup"
      fill_in "email", with: data.email
      fill_in "new-password", with: "tz123456"
      click_button "Sign up"

      user_rows = visit_admin_sql "select id from users where email = '#{data.email}'"
      user_id = user_rows[0]["id"]

      # Set email delivery channel
      if data.email_delivery
        user_settings_rows = visit_admin_sql <<-SQL
          update user_settings
          set delivery_channel = 'email'
          where user_id = #{user_id}
          returning *
        SQL
        assert_equal 1, user_settings_rows.length
      end

      # Assert timezone
      visit_dev "settings"
      assert_selector "option[value='#{data.timezone}'][selected='selected']"

      # Assert both jobs got scheduled at the right time
      update_rss_job_rows = visit_admin_sql <<-SQL
        select run_at,
          (regexp_match(handler, concat(E'arguments:\n  - #{user_id}\n  - ''([0-9-]+)''')))[1] as date
        from delayed_jobs
        where handler like '%UpdateRssJob%'
          and handler like E'%\\n  - #{user_id}\\n%'
      SQL
      assert_equal 1, update_rss_job_rows.length
      expected_rss_run_at = today_local.advance(hours: 2)
      actual_rss_run_at = DateTime.parse(update_rss_job_rows[0]["run_at"])
      assert_in_delta expected_rss_run_at, actual_rss_run_at, 60
      today_date_str = ScheduleHelper::date_str(today_utc)
      assert_equal today_date_str, update_rss_job_rows[0]["date"]

      email_posts_job_rows = visit_admin_sql <<-SQL
        select run_at,
          (regexp_match(handler, concat(E'arguments:\n  - #{user_id}\n  - ''([0-9-]+)''')))[1] as date
        from delayed_jobs
        where handler like '%EmailPostsJob%'
          and handler like E'%\\n  - #{user_id}\\n%'
      SQL
      assert_equal 1, email_posts_job_rows.length
      expected_email_run_at = today_local.advance(hours: 5)
      actual_email_run_at = DateTime.parse(email_posts_job_rows[0]["run_at"])
      assert_in_delta expected_email_run_at, actual_email_run_at, 60
      assert_equal today_date_str, email_posts_job_rows[0]["date"]

      # Cleanup
      visit_admin "travel_back_v2"
      assert_in_delta DateTime.now.utc, DateTime.parse(page.document.text), 60
      visit_admin "reschedule_user_jobs"
      assert_equal "OK", page.document.text
    end
  end
end
