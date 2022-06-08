require "application_system_test_case"

class MiscSystemTest < ApplicationSystemTestCase
  test "Double schedule" do
    email = "test_pst@test.com"

    visit_dev "login"
    fill_in "email", with: email
    fill_in "current-password", with: "tz123456"
    click_button "Sign in"

    visit_admin "destroy_user_subscriptions"
    assert_equal "OK", page.document.text

    today_utc = DateTime.new(2022, 6, 1)
    today_local = today_utc.advance(hours: 7)
    today_local_1am = today_local.advance(hours: 1)
    visit_admin "travel_to_v2?timestamp=#{today_local_1am}"
    assert_equal today_local_1am, page.document.text
    visit_admin "reschedule_update_rss_job"
    assert_equal "OK", page.document.text

    user_rows = visit_admin_sql "select id from users where email = '#{email}'"
    user_id = user_rows[0]["id"]

    initial_job_rows = visit_admin_sql <<-SQL
      select id from delayed_jobs
      where handler like '%UpdateRssJob%'
        and handler like E'%\\n  - #{user_id}\\n%'
    SQL
    assert_equal 1, initial_job_rows.length
    initial_job_id = initial_job_rows[0]["id"]

    visit_dev "subscriptions/add"
    fill_in "start_url", with: "https://ilidemi.github.io/dummy-blogs/1a/rss.xml"
    click_button "Go"

    while page.has_css?("#progress_count")
      sleep(100)
    end

    if page.has_css?("#confirm_section")
      click_button "Continue"
    end

    click_button "wed_add"
    click_button "Continue"
    subscription_id = /[0-9]+/.match(page.current_path)[0]

    # Duplicate the job
    visit_admin_sql <<-SQL
      insert into delayed_jobs (priority, attempts, handler, run_at, queue, created_at, updated_at)
      select priority, attempts, handler, run_at, queue, created_at, updated_at
      from delayed_jobs
      where id = #{initial_job_id}
    SQL
    duplicate_job_rows = visit_admin_sql <<-SQL
      select id from delayed_jobs
      where handler like '%UpdateRssJob%'
        and handler like E'%\\n  - #{user_id}\\n%'
    SQL
    assert_equal 2, duplicate_job_rows.length

    today_local_3am = today_local.advance(hours: 3)
    visit_admin "travel_to_v2?timestamp=#{today_local_3am}"
    assert_equal today_local_3am, page.document.text
    visit_admin "wait_for_update_rss_job"

    # Assert 1 job for tomorrow and 1 published post
    rescheduled_job_rows = visit_admin_sql <<-SQL
      select id from delayed_jobs
      where handler like '%UpdateRssJob%'
        and handler like E'%\\n  - #{user_id}\\n%'
    SQL
    assert_equal 1, rescheduled_job_rows.length

    published_post_rows = visit_admin_sql <<-SQL
      select id from subscription_posts
      where subscription_id = #{subscription_id}
      and published_at_local_date = '2022-06-01'
    SQL
    assert_equal 1, published_post_rows.length

    # Cleanup
    visit_admin "travel_back_v2"
    assert_in_delta DateTime.now.utc, DateTime.parse(page.document.text), 60
    visit_admin "reschedule_update_rss_job"
    assert_equal "OK", page.document.text

    visit_dev "logout"
  end
end