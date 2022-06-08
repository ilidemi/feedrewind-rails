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
end
