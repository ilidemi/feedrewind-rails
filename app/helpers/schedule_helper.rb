module ScheduleHelper
  def ScheduleHelper::day_of_week(date)
    date
      .strftime('%a')
      .downcase
  end

  def ScheduleHelper::date_str(date)
    date.strftime("%Y-%m-%d")
  end

  def ScheduleHelper::is_early_morning(local_datetime)
    local_datetime.hour < 5
  end

  def ScheduleHelper::utc_str(datetime)
    if datetime.is_a?(Time)
      raise "Expected utc time" unless datetime.utc_offset == 0
    elsif datetime.is_a?(DateTime)
      raise "Expected utc datetime" unless datetime.offset == 0
    else
      raise "Unknown datetime class: #{datetime.class}"
    end

    datetime.strftime("%Y-%m-%d %H:%M:%S")
  end
end
