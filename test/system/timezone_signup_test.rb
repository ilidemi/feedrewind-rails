require "application_system_test_case"

class TimezoneSignupTest < ApplicationSystemTestCase
  email_by_timezone = {
    "Pacific/Auckland" => "test_nz@test.com",
    "America/Los_Angeles" => "test_pst@test.com"
  }

  SignupData = Struct.new(:email, :timezone)
  signup_data = email_by_timezone.map do |timezone, email|
    SignupData.new(email, timezone)
  end

  signup_data.each do |data|
    test "Timezone #{data.timezone} sign up" do
      visit_admin "destroy_user?email=#{data.email}"
      assert_includes(%w[OK NotFound], page.document.text)

      page.driver.browser.execute_cdp(
        "Emulation.setTimezoneOverride",
        timezoneId: data.timezone
      )
      visit_dev "signup"
      fill_in "email", with: data.email
      fill_in "new-password", with: "tz123456"
      click_button "Sign up"

      visit_admin "user_timezone?email=#{data.email}"
      assert_equal data.timezone, page.document.text
    end
  end
end
