require "application_system_test_case"

class MiscSystemTest < ApplicationSystemTestCase
  test "Update from feed" do
    visit_dev "login"
    fill_in "email", with: "test_pst@test.com"
    fill_in "current-password", with: "tz123456"
    click_button "Sign in"

    visit_admin "destroy_user_subscriptions"
    assert_equal "OK", page.document.text

    visit_dev "admin/add_blog"
    fill_in "name", with: "1man"
    fill_in "feed_url", with: "https://ilidemi.github.io/dummy-blogs/1man/rss.xml"
    fill_in "url", with: "https://ilidemi.github.io/dummy-blogs/1man/"
    fill_in "posts", with: <<-LIST
      https://ilidemi.github.io/dummy-blogs/1man/post2 post2
      https://ilidemi.github.io/dummy-blogs/1man/post3 post3
      https://ilidemi.github.io/dummy-blogs/1man/post4 post4
      https://ilidemi.github.io/dummy-blogs/1man/post5 post5
    LIST
    select "update_from_feed_or_fail", from: "update_action"
    click_button "Save"

    status_rows = visit_admin_sql <<-SQL
      select id, status from blogs
      where feed_url = 'https://ilidemi.github.io/dummy-blogs/1man/rss.xml' and
        version = #{Blog::LATEST_VERSION}
    SQL
    assert_equal "manually_inserted", status_rows[0]["status"]
    blog_id = status_rows[0]["id"]

    deleted_rows = visit_admin_sql <<-SQL
      delete from blog_discarded_feed_entries where blog_id = #{blog_id} returning *
    SQL
    assert_equal 1, deleted_rows.length

    visit_dev "subscriptions/add"
    fill_in "start_url", with: "https://ilidemi.github.io/dummy-blogs/1man/rss.xml"
    click_button "Go"

    click_button "wed_add", wait: 2
    click_button "Continue"
    assert_selector "#arrival_msg"

    subscription_id = /[0-9]+/.match(page.current_path)[0]
    visit_dev "subscriptions/#{subscription_id}"
    total_count = /[0-9]+$/.match(page.find("#published_count").text)[0].to_i
    assert_equal 5, total_count
  end
end