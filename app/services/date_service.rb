module DateService
  PACIFIC_TIME_ZONE = 'Pacific Time (US & Canada)'

  def DateService::day_of_week
    Date.today
        .in_time_zone(PACIFIC_TIME_ZONE)
        .strftime('%a')
        .downcase
  end

  def DateService::now
    DateTime
      .now
      .in_time_zone(PACIFIC_TIME_ZONE)
  end
end
