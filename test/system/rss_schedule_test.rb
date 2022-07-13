require "application_system_test_case"

class RssScheduleTest < ApplicationSystemTestCase
  timezone_by_email = {
    "test_pst@test.com" => "America/Los_Angeles",
    "test_nz@test.com" => "Pacific/Auckland",
  }

  # @formatter:off
  ScheduleOutput =                   Struct.new(        :preview_bfr,    :arrival_msg,        :pub_crt, :preview_crt,           :pub_late, :preview_late,         :preview_mdnt,                 :pub_tmrw, :preview_tmrw)
  schedule_outputs = {
    job_today_job_tomorrow:          ScheduleOutput.new([:td, :tm, :da], [:one, :will, :td],  0, [[],         [:td, :tm, :da]], 1, [[:td],      [:tm, :da]     ], [[:ys],      [:td, :tm]     ], 2, [[:ys, :td], [:tm]]),
    job_today_no_tomorrow:           ScheduleOutput.new([:td, :da],      [:one, :will, :td],  0, [[],         [:td, :da]     ], 1, [[:td],      [:da]          ], [[:ys],      [:tm]          ], 1, [[:ys],      [:tm]]),
    no_today_job_tomorrow:           ScheduleOutput.new([:tm, :da],      [:one, :will, :tm],  0, [[],         [:tm, :da]     ], 0, [[],         [:tm, :da]     ], [[],         [:td, :tm]     ], 1, [[:td],      [:tm]]),
    no_today_no_tomorrow:            ScheduleOutput.new([:da],           [:one, :will, :da],  0, [[],         [:da]          ], 0, [[],         [:da]          ], [[],         [:tm]          ], 0, [[],         [:tm]]),
    init_today_job_tomorrow:         ScheduleOutput.new([:td, :tm, :da], [:one, :has],        1, [[:td],      [:tm, :da]     ], 1, [[:td],      [:tm, :da]     ], [[:ys],      [:td, :tm]     ], 2, [[:ys, :td], [:tm]]),
    init_today_no_tomorrow:          ScheduleOutput.new([:td, :da],      [:one, :has],        1, [[:td],      [:da]          ], 1, [[:td],      [:da]          ], [[:ys],      [:tm]          ], 1, [[:ys],      [:tm]]),
    x2_job_today_job_tomorrow:       ScheduleOutput.new([:td, :td, :tm], [:many, :will, :td], 0, [[],         [:td, :td, :tm]], 2, [[:td, :td], [:tm, :tm, :da]], [[:ys, :ys], [:td, :td, :tm]], 4, [[:el, :td], [:tm]]),
    x2_job_today_no_tomorrow:        ScheduleOutput.new([:td, :td, :da], [:many, :will, :td], 0, [[],         [:td, :td, :da]], 2, [[:td, :td], [:da, :da]     ], [[:ys, :ys], [:tm, :tm]     ], 2, [[:ys, :ys], [:tm]]),
    x2_no_today_job_tomorrow:        ScheduleOutput.new([:tm, :tm, :da], [:many, :will, :tm], 0, [[],         [:tm, :tm, :da]], 0, [[],         [:tm, :tm, :da]], [[],         [:td, :td, :tm]], 2, [[:td, :td], [:tm]]),
    x2_no_today_no_tomorrow:         ScheduleOutput.new([:da, :da],      [:many, :will, :da], 0, [[],         [:da, :da]     ], 0, [[],         [:da, :da]     ], [[],         [:tm, :tm]     ], 0, [[],         [:tm]]),
    x2_init_today_job_tomorrow:      ScheduleOutput.new([:td, :td, :tm], [:many, :have],      2, [[:td, :td], [:tm, :tm, :da]], 2, [[:td, :td], [:tm, :tm, :da]], [[:ys, :ys], [:td, :td, :tm]], 4, [[:el, :td], [:tm]]),
    x2_init_today_no_tomorrow:       ScheduleOutput.new([:td, :td, :da], [:many, :have],      2, [[:td, :td], [:da, :da]     ], 2, [[:td, :td], [:da, :da]     ], [[:ys, :ys], [:tm, :tm]     ], 2, [[:ys, :ys], [:tm]]),
  }
  # @formatter:on

  ScheduleData = Struct.new(:email, :count, :crt_time, :pub_today, :pub_tomorrow, :output_name)
  schedule_data = [
    # @formatter:off
    ScheduleData.new("test_pst@test.com", 1, :v_early, true,  true,  :job_today_job_tomorrow),
    ScheduleData.new("test_pst@test.com", 1, :v_early, true,  false, :job_today_no_tomorrow),
    ScheduleData.new("test_pst@test.com", 1, :v_early, false, true,  :no_today_job_tomorrow),
    ScheduleData.new("test_pst@test.com", 1, :early,   true,  true,  :init_today_job_tomorrow),
    ScheduleData.new("test_pst@test.com", 1, :early,   true,  false, :init_today_no_tomorrow),
    ScheduleData.new("test_pst@test.com", 1, :early,   false, true,  :no_today_job_tomorrow),
    ScheduleData.new("test_pst@test.com", 1, :day,     true,  true,  :no_today_job_tomorrow),
    ScheduleData.new("test_pst@test.com", 1, :day,     true,  false, :no_today_no_tomorrow),
    ScheduleData.new("test_pst@test.com", 1, :day,     false, true,  :no_today_job_tomorrow),
    ScheduleData.new("test_nz@test.com",  2, :v_early, true,  true,  :x2_job_today_job_tomorrow),
    ScheduleData.new("test_nz@test.com",  2, :v_early, true,  false, :x2_job_today_no_tomorrow),
    ScheduleData.new("test_nz@test.com",  2, :v_early, false, true,  :x2_no_today_job_tomorrow),
    ScheduleData.new("test_nz@test.com",  2, :early,   true,  true,  :x2_init_today_job_tomorrow),
    ScheduleData.new("test_nz@test.com",  2, :early,   true,  false, :x2_init_today_no_tomorrow),
    ScheduleData.new("test_nz@test.com",  2, :early,   false, true,  :x2_no_today_job_tomorrow),
    ScheduleData.new("test_nz@test.com",  2, :day,     true,  true,  :x2_no_today_job_tomorrow),
    ScheduleData.new("test_nz@test.com",  2, :day,     true,  false, :x2_no_today_no_tomorrow),
    ScheduleData.new("test_nz@test.com",  2, :day,     false, true,  :x2_no_today_job_tomorrow),
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

      late_timestamp = today_local.advance(hours: 23)
      midnight_timestamp = today_local.advance(days: 1, minutes: 1)
      tomorrow_timestamp = today_local.advance(days: 1, hours: 3, minutes: 1)

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

      visit_dev "subscriptions/add"
      fill_in "start_url", with: "https://ilidemi.github.io/dummy-blogs/1a/rss.xml"
      click_button "Go"

      while page.has_css?("#progress_count")
        sleep(0.1)
      end

      if page.has_css?("#confirm_section")
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
      expected_arrival_msg_a = ["First"]

      case output.arrival_msg[0]
      when :one
        expected_arrival_msg_a << "entry"
      when :many
        expected_arrival_msg_a << "entries"
      else
        raise "Unexpected arrival entries count: #{output.arrival_msg[0]}"
      end

      case output.arrival_msg[1]
      when :will
        expected_arrival_msg_a << "will arrive"
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
        expected_arrival_msg_a << "has already arrived"
      when :have
        expected_arrival_msg_a << "have already arrived"
      else
        raise "Unexpected arrival verb: #{output.arrival_msg[1]}"
      end

      expected_arrival_msg = expected_arrival_msg_a.join(" ")
      assert_selector "#arrival_msg", text: expected_arrival_msg

      subscription_id = /[0-9]+/.match(page.current_path)[0]
      subscription_path = "subscriptions/#{subscription_id}"

      # Assert pub_crt
      visit_dev subscription_path
      published_count = /^[0-9]+/.match(page.find("#published_count").text)[0].to_i
      assert_equal output.pub_crt, published_count

      # Assert preview_crt
      visit_dev subscription_path unless page.current_path == subscription_path
      assert_schedule_preview(output.preview_crt[0], output.preview_crt[1])

      # Assert pub_late
      visit_admin "travel_to_v2?timestamp=#{late_timestamp}"
      assert_equal late_timestamp, page.document.text
      visit_admin "wait_for_publish_posts_job"
      assert_equal "OK", page.document.text
      visit_dev subscription_path
      published_count = /^[0-9]+/.match(page.find("#published_count").text)[0].to_i
      assert_equal output.pub_late, published_count

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
      visit_dev subscription_path
      published_count = /^[0-9]+/.match(page.find("#published_count").text)[0].to_i
      assert_equal output.pub_tmrw, published_count

      # Assert preview_tmrw
      visit_dev subscription_path unless page.current_path == subscription_path
      assert_schedule_preview(output.preview_tmrw[0], output.preview_tmrw[1])

      # Cleanup
      visit_admin "travel_back_v2"
      assert_in_delta DateTime.now.utc, DateTime.parse(page.document.text), 60
      visit_admin "reschedule_user_job"
      assert_equal "OK", page.document.text

      visit_dev "logout"
    end
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
