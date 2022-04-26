module ScheduleHelper
  class ScheduleDate
    PACIFIC_TIME_ZONE = 'Pacific Time (US & Canada)'
    PSQL_PACIFIC_TIME_ZONE = 'PDT'

    def ScheduleDate::now
      ScheduleDate.new(
        DateTime
          .now
          .in_time_zone(PACIFIC_TIME_ZONE)
      )
    end

    def initialize(date)
      @date = date
    end

    def day_of_week
      @date
        .strftime('%a')
        .downcase
    end

    def is_early_morning
      @date.hour < 5
    end

    def date_str
      @date.strftime("%Y-%m-%d")
    end

    def advance_till_midnight
      ScheduleDate.new(
        @date
          .advance(days: 1)
          .midnight
      )
    end

    attr_reader :date
  end

  def ScheduleHelper::now
    ScheduleDate::now
  end
end
