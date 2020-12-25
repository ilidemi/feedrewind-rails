module BlogsHelper
  def BlogsHelper.feed_url(request, blog)
    "#{request.protocol}#{request.host_with_port}/#{blog.name}/feed"
  end

  def BlogsHelper.days_of_week_from_params(schedule_params)
    days_of_week = []
    days_of_week << 'mon' if schedule_params[:schedule_mon] == '1'
    days_of_week << 'tue' if schedule_params[:schedule_tue] == '1'
    days_of_week << 'wed' if schedule_params[:schedule_wed] == '1'
    days_of_week << 'thu' if schedule_params[:schedule_thu] == '1'
    days_of_week << 'fri' if schedule_params[:schedule_fri] == '1'
    days_of_week << 'sat' if schedule_params[:schedule_sat] == '1'
    days_of_week << 'sun' if schedule_params[:schedule_sun] == '1'
    days_of_week
  end
end
