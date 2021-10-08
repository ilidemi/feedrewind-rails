class ProgressLogger
  def initialize(progress_saver)
    @progress_saver = progress_saver
    @status_str = ''
  end

  def log_html
    @status_str << 'h'
  end

  def log_and_save_puppeteer
    @status_str << 'p'
    @progress_saver.save_status(@status_str)
  end

  def log_historical
    @status_str << 'H'
  end

  def log_and_save_postprocessing
    @status_str << 'F'
    @progress_saver.save_status(@status_str)
  end

  def log_and_save_postprocessing_remaining(remaining_count)
    @status_str << 'F'
    @status_str << "#{remaining_count}"
    @progress_saver.save_status(@status_str)
  end

  def log_count(count)
    @progress_saver.save_count(count)
  end

  def save_status
    @progress_saver.save_status(@status_str)
  end
end