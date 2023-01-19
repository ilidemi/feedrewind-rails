require "application_system_test_case"

class EmailScheduleTest < ApplicationSystemTestCase
  timezone_by_email = {
    "test_email_pst@feedrewind.com" => "America/Los_Angeles",
    "test_email_nz@feedrewind.com" => "Pacific/Auckland",
  }

  # @formatter:off
  ScheduleOutput =             Struct.new(        :preview_bfr,    :arrival_msg,        :pub_crt, :preview_crt,   :pub_late, :last_ts_late, :preview_late, :preview_mdnt,                :pub_tmrw, :last_ts_tmrw, :preview_tmrw)
  schedule_outputs = {
    job_today_job_tomorrow:    ScheduleOutput.new([:td, :tm, :da], [:one, :will, :td],  1, [[], [:td, :tm, :da]], 2, :td,  [[:td],      [:tm, :da]     ], [[:ys],      [:td, :tm]     ], 3, :td,  [[:ys, :td], [:tm]     ]),
    job_today_no_tomorrow:     ScheduleOutput.new([:td, :da],      [:one, :will, :td],  1, [[], [:td, :da]     ], 2, :td,  [[:td],      [:da]          ], [[:ys],      [:tm]          ], 2, :ys,  [[:ys],      [:tm]     ]),
    no_today_job_tomorrow:     ScheduleOutput.new([:tm, :da],      [:one, :will, :tm],  1, [[], [:tm, :da]     ], 1, :crt, [[],         [:tm, :da]     ], [[],         [:td, :tm]     ], 2, :td,  [[:td],      [:tm]     ]),
    no_today_no_tomorrow:      ScheduleOutput.new([:da],           [:one, :will, :da],  1, [[], [:da]          ], 1, :crt, [[],         [:da]          ], [[],         [:tm]          ], 1, :crt, [[],         [:tm]     ]),
    x2_job_today_job_tomorrow: ScheduleOutput.new([:td, :td, :tm], [:many, :will, :td], 1, [[], [:td, :td, :tm]], 3, :td,  [[:td, :td], [:tm, :tm, :da]], [[:ys, :ys], [:td, :td, :tm]], 5, :td,  [[:el, :td], [:tm, :tm]]),
    x2_job_today_no_tomorrow:  ScheduleOutput.new([:td, :td, :da], [:many, :will, :td], 1, [[], [:td, :td, :da]], 3, :td,  [[:td, :td], [:da, :da]     ], [[:ys, :ys], [:tm, :tm]     ], 3, :ys,  [[:ys, :ys], [:tm, :tm]]),
    x2_no_today_job_tomorrow:  ScheduleOutput.new([:tm, :tm, :da], [:many, :will, :tm], 1, [[], [:tm, :tm, :da]], 1, :crt, [[],         [:tm, :tm, :da]], [[],         [:td, :td, :tm]], 3, :td,  [[:td, :td], [:tm, :tm]]),
    x2_no_today_no_tomorrow:   ScheduleOutput.new([:da, :da],      [:many, :will, :da], 1, [[], [:da, :da]     ], 1, :crt, [[],         [:da, :da]     ], [[],         [:tm, :tm]     ], 1, :crt, [[],         [:tm, :tm]]),
  }
  # @formatter:on

  ScheduleData = Struct.new(:email, :count, :crt_time, :pub_today, :pub_tomorrow, :output_name)
  schedule_data = [
    # @formatter:off
    ScheduleData.new("test_email_pst@feedrewind.com", 1, :v_early, true,  true,  :job_today_job_tomorrow),
    ScheduleData.new("test_email_pst@feedrewind.com", 1, :v_early, true,  false, :job_today_no_tomorrow),
    ScheduleData.new("test_email_pst@feedrewind.com", 1, :v_early, false, true,  :no_today_job_tomorrow),
    ScheduleData.new("test_email_pst@feedrewind.com", 1, :early,   true,  true,  :job_today_job_tomorrow),
    ScheduleData.new("test_email_pst@feedrewind.com", 1, :early,   true,  false, :job_today_no_tomorrow),
    ScheduleData.new("test_email_pst@feedrewind.com", 1, :early,   false, true,  :no_today_job_tomorrow),
    ScheduleData.new("test_email_pst@feedrewind.com", 1, :day,     true,  true,  :no_today_job_tomorrow),
    ScheduleData.new("test_email_pst@feedrewind.com", 1, :day,     true,  false, :no_today_no_tomorrow),
    ScheduleData.new("test_email_pst@feedrewind.com", 1, :day,     false, true,  :no_today_job_tomorrow),
    ScheduleData.new("test_email_nz@feedrewind.com",  2, :v_early, true,  true,  :x2_job_today_job_tomorrow),
    ScheduleData.new("test_email_nz@feedrewind.com",  2, :v_early, true,  false, :x2_job_today_no_tomorrow),
    ScheduleData.new("test_email_nz@feedrewind.com",  2, :v_early, false, true,  :x2_no_today_job_tomorrow),
    ScheduleData.new("test_email_nz@feedrewind.com",  2, :early,   true,  true,  :x2_job_today_job_tomorrow),
    ScheduleData.new("test_email_nz@feedrewind.com",  2, :early,   true,  false, :x2_job_today_no_tomorrow),
    ScheduleData.new("test_email_nz@feedrewind.com",  2, :early,   false, true,  :x2_no_today_job_tomorrow),
    ScheduleData.new("test_email_nz@feedrewind.com",  2, :day,     true,  true,  :x2_no_today_job_tomorrow),
    ScheduleData.new("test_email_nz@feedrewind.com",  2, :day,     true,  false, :x2_no_today_no_tomorrow),
    ScheduleData.new("test_email_nz@feedrewind.com",  2, :day,     false, true,  :x2_no_today_job_tomorrow)
    # @formatter:on
  ]

  schedule_data.each do |data|
    test_name = data.deconstruct_keys(nil).map { |k, v| "#{k}=#{v}" }.join(" ")
    test "Timezone schedule #{test_name}" do
      output = schedule_outputs[data.output_name]
      timezone = timezone_by_email[data.email]

      today_utc = DateTime.new(2022, 6, 1).utc
      case timezone
      when "America/Los_Angeles"
        today_local = today_utc.advance(hours: 7)
      when "Pacific/Auckland"
        today_local = today_utc.advance(hours: -12)
      else
        raise "Unknown timezone: #{timezone}"
      end

      case data.crt_time
      when :v_early
        creation_timestamp = today_local.advance(hours: 1)
      when :early
        creation_timestamp = today_local.advance(hours: 4)
      when :day
        creation_timestamp = today_local.advance(hours: 13)
      else
        raise "Unknown crt_time: #{data.crt_time}"
      end

      today_email_timestamp = today_local.advance(hours: 5)
      late_timestamp = today_local.advance(hours: 23)
      midnight_timestamp = today_local.advance(days: 1, minutes: 1)
      tomorrow_email_timestamp = today_local.advance(days: 1, hours: 5)
      tomorrow_timestamp = today_local.advance(days: 1, hours: 6, minutes: 1)

      visit_dev "login"
      fill_in "email", with: data.email
      fill_in "current-password", with: "tz123456"
      click_button "Sign in"

      visit_admin "destroy_user_subscriptions"
      assert_equal "OK", page.document.text

      visit_admin "travel_to_v2?timestamp=#{creation_timestamp}"
      assert_equal creation_timestamp, page.document.text
      visit_admin "reschedule_user_job"
      assert_equal "OK", page.document.text

      email_metadata = RandomId::generate_random_bigint
      visit_admin "set_email_metadata?value=#{email_metadata}"
      assert_equal "OK", page.document.text

      visit_dev "subscriptions/add"
      fill_in "start_url", with: "https://ilidemi.github.io/dummy-blogs/1a/rss.xml"
      click_button "Go"

      while page.has_css?("#progress_count")
        sleep(0.1)
      end

      if page.has_css?("#confirm_section_0")
        click_button "Continue"
      end

      if data.pub_today
        data.count.times { click_button "wed_add" }
      end

      if data.pub_tomorrow
        data.count.times { click_button "thu_add" }
      end

      data.count.times { click_button "fri_add" }

      # Assert preview_bfr
      assert_schedule_preview([], output.preview_bfr)

      click_button "Continue"

      # Assert arrival_msg
      expected_arrival_msg_a = []

      case output.arrival_msg[1]
      when :will
        case output.arrival_msg[0]
        when :one
          expected_arrival_msg_a << "First entry"
        when :many
          expected_arrival_msg_a << "First entries"
        else
          raise "Unexpected arrival entries count: #{output.arrival_msg[0]}"
        end

        expected_arrival_msg_a << "will be sent on"

        case output.arrival_msg[2]
        when :td
          expected_arrival_msg_a << "Wednesday, June 1st"
        when :tm
          expected_arrival_msg_a << "Thursday, June 2nd"
        when :da
          expected_arrival_msg_a << "Friday, June 3rd"
        else
          raise "Unexpected arrival date: #{output.arrival_msg[2]}"
        end
      when :has
        expected_arrival_msg_a << "We've just sent the first entry"
      when :have
        expected_arrival_msg_a << "We've just sent the first entries"
      else
        raise "Unexpected arrival verb: #{output.arrival_msg[1]}"
      end

      expected_arrival_msg_a << "to #{data.email}"

      expected_arrival_msg = expected_arrival_msg_a.join(" ")
      assert_selector "#arrival_msg", text: expected_arrival_msg

      subscription_id = /[0-9]+/.match(page.current_path)[0]
      subscription_path = "subscriptions/#{subscription_id}"

      # Assert pub_crt
      visit_admin "assert_email_count_with_metadata?value=#{email_metadata}&count=#{output.pub_crt}&last_timestamp=#{ScheduleHelper::utc_str(creation_timestamp)}&last_tag=subscription_initial"
      assert_equal "OK", page.document.text

      # Assert preview_crt
      visit_dev subscription_path unless page.current_path == subscription_path
      assert_schedule_preview(output.preview_crt[0], output.preview_crt[1])

      # Assert pub_late
      visit_admin "travel_to_v2?timestamp=#{late_timestamp}"
      assert_equal late_timestamp, page.document.text
      visit_admin "wait_for_publish_posts_job"
      assert_equal "OK", page.document.text
      case output.last_ts_late
      when :crt
        last_timestamp_late = creation_timestamp
        last_tag_late = "subscription_initial"
      when :td
        last_timestamp_late = today_email_timestamp
        last_tag_late = "subscription_post"
      else
        raise "Unknown last_ts_late: #{output.last_ts_late}"
      end
      visit_admin "assert_email_count_with_metadata?value=#{email_metadata}&count=#{output.pub_late}&last_timestamp=#{ScheduleHelper::utc_str(last_timestamp_late)}&last_tag=#{last_tag_late}"
      assert_equal "OK", page.document.text

      # Assert preview_late
      visit_dev subscription_path unless page.current_path == subscription_path
      assert_schedule_preview(output.preview_late[0], output.preview_late[1])

      # Assert preview_mdnt
      visit_admin "travel_to_v2?timestamp=#{midnight_timestamp}"
      assert_equal midnight_timestamp, page.document.text
      visit_dev subscription_path
      assert_schedule_preview(output.preview_mdnt[0], output.preview_mdnt[1])

      # Assert pub_tmrw
      visit_admin "travel_to_v2?timestamp=#{tomorrow_timestamp}"
      assert_equal tomorrow_timestamp, page.document.text
      visit_admin "wait_for_publish_posts_job"
      assert_equal "OK", page.document.text
      case output.last_ts_tmrw
      when :crt
        last_timestamp_tmrw = creation_timestamp
        last_tag_tmrw = "subscription_initial"
      when :ys
        last_timestamp_tmrw = today_email_timestamp
        last_tag_tmrw = "subscription_post"
      when :td
        last_timestamp_tmrw = tomorrow_email_timestamp
        last_tag_tmrw = "subscription_post"
      else
        raise "Unknown last_ts_late: #{output.last_ts_late}"
      end
      visit_admin "assert_email_count_with_metadata?value=#{email_metadata}&count=#{output.pub_tmrw}&last_timestamp=#{ScheduleHelper::utc_str(last_timestamp_tmrw)}&last_tag=#{last_tag_tmrw}"
      assert_equal "OK", page.document.text

      # Assert preview_tmrw
      visit_dev subscription_path unless page.current_path == subscription_path
      assert_schedule_preview(output.preview_tmrw[0], output.preview_tmrw[1])

      # Cleanup
      visit_admin "travel_back_v2"
      assert_in_delta DateTime.now.utc, DateTime.parse(page.document.text), 60
      visit_admin "reschedule_user_job"
      assert_equal "OK", page.document.text
      visit_admin "delete_email_metadata"
      assert_equal "OK", page.document.text

      visit_dev "logout"
    end
  end

  test "Final item email" do
    today_utc = DateTime.new(2022, 6, 1).utc
    today_local = today_utc.advance(hours: 7)
    creation_timestamp = today_local.advance(hours: 4)
    today_email_timestamp = today_local.advance(hours: 5)
    today_final_email_timestamp = today_local.advance(hours: 5, minutes: 1)

    visit_dev "login"
    fill_in "email", with: "test_email_pst@feedrewind.com"
    fill_in "current-password", with: "tz123456"
    click_button "Sign in"

    visit_admin "destroy_user_subscriptions"
    assert_equal "OK", page.document.text

    visit_admin "travel_to_v2?timestamp=#{creation_timestamp}"
    assert_equal creation_timestamp, page.document.text
    visit_admin "reschedule_user_job"
    assert_equal "OK", page.document.text

    email_metadata = RandomId::generate_random_bigint
    visit_admin "set_email_metadata?value=#{email_metadata}"
    assert_equal "OK", page.document.text

    visit_dev "subscriptions/add"
    fill_in "start_url", with: "https://ilidemi.github.io/dummy-blogs/1a/rss.xml"
    click_button "Go"

    while page.has_css?("#progress_count")
      sleep(0.1)
    end

    if page.has_css?("#confirm_section_0")
      click_button "Continue"
    end

    20.times { click_button "wed_add" }
    click_button "Continue"
    assert_selector "#arrival_msg"

    # Assert initial item published
    visit_admin "assert_email_count_with_metadata?value=#{email_metadata}&count=1&last_timestamp=#{ScheduleHelper::utc_str(creation_timestamp)}&last_tag=subscription_initial"
    assert_equal "OK", page.document.text

    # Assert all 20 items published
    visit_admin "travel_to_v2?timestamp=#{today_email_timestamp}"
    assert_equal today_email_timestamp, page.document.text
    visit_admin "wait_for_publish_posts_job"
    assert_equal "OK", page.document.text
    visit_admin "assert_email_count_with_metadata?value=#{email_metadata}&count=21&last_timestamp=#{ScheduleHelper::utc_str(today_email_timestamp)}&last_tag=subscription_post"
    assert_equal "OK", page.document.text

    # Assert final item published
    visit_admin "travel_to_v2?timestamp=#{today_final_email_timestamp}"
    assert_equal today_final_email_timestamp, page.document.text
    visit_admin "assert_email_count_with_metadata?value=#{email_metadata}&count=22&last_timestamp=#{ScheduleHelper::utc_str(today_final_email_timestamp)}&last_tag=subscription_final"
    assert_equal "OK", page.document.text
  end

  def assert_schedule_preview(expected_prev, expected_next)
    tbody = page.find("#schedule_preview").find("tbody")
    prev_rows = tbody.all("tr", class: "prev_post")
    expected_prev.each_with_index do |expected_date, i|
      row = prev_rows[i]
      row_date = row.find(:xpath, ".//td[2]").text
      if expected_date == :el
        assert_equal "…", row_date
      elsif expected_date == :ys
        assert_equal "Yesterday", row_date
      elsif expected_date == :td
        assert_equal "Today", row_date
      else
        raise "Unknown date: #{expected_date}"
      end
    end
    next_rows = tbody.all("tr", class: "next_post")
    expected_next.each_with_index do |expected_date, i|
      row = next_rows[i]
      row_date = row.find(:xpath, ".//td[2]").text
      if expected_date == :td
        assert_equal "Today", row_date
      elsif expected_date == :tm
        assert_equal "Tomorrow", row_date
      elsif expected_date == :da
        assert_equal "Fri, June 3", row_date
      else
        raise "Unknown date: #{expected_date}"
      end
    end
  end
end
