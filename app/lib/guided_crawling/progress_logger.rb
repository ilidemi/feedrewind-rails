class ProgressLogger
  def initialize(progress_saver)
    @progress_saver = progress_saver
    @status_str = ''
    @prev_is_postprocessing = nil
    @prev_fetched_count = nil
    @prev_remaining_count = nil
  end

  def log_html
    @status_str << 'h'
  end

  # Supposed to be called after log_html but not any others
  def save_status
    @progress_saver.save_status(@status_str)
    track_regressions(false, nil, :undefined)
  end

  def log_and_save_puppeteer_start
    @status_str << 'p'
    @progress_saver.save_status(@status_str)
    track_regressions(false, nil, :undefined)
  end

  def log_and_save_puppeteer
    @status_str << 'P'
    @progress_saver.save_status(@status_str)
    track_regressions(false, nil, :undefined)
  end

  def log_and_save_postprocessing
    @status_str << 'F'
    @progress_saver.save_status(@status_str)
    track_regressions(true, nil, :undefined)
  end

  def log_and_save_postprocessing_reset_count
    @status_str << 'F'
    @progress_saver.save_status_and_count(@status_str, nil)
    track_regressions(true, nil, nil)
  end

  def log_and_save_postprocessing_counts(fetched_count, remaining_count)
    @status_str << 'F'
    @status_str << "#{remaining_count}"
    @progress_saver.save_status_and_count(@status_str, fetched_count)
    track_regressions(true, remaining_count, fetched_count)
  end

  def log_and_save_fetched_count(fetched_count)
    @progress_saver.save_count(fetched_count)
    track_regressions(:undefined, :undefined, fetched_count)
  end

  private

  def track_regressions(is_postprocessing, remaining_count, fetched_count)
    regressions = []
    kv_bag = {}

    if is_postprocessing != :undefined
      if @prev_is_postprocessing == true && is_postprocessing != true
        regressions << "postprocessing_reset"
        kv_bag[:status] = @status_str.dup
      end
      @prev_is_postprocessing = is_postprocessing
    end

    if remaining_count != :undefined
      if @prev_remaining_count != nil && (remaining_count.nil? || remaining_count >= @prev_remaining_count)
        regressions << "remaining_count_up"
        kv_bag[:prev_remaining_count] = @prev_remaining_count.dup
        kv_bag[:new_remaining_count] = remaining_count
      end
      @prev_remaining_count = remaining_count
    end

    if fetched_count != :undefined
      if @prev_fetched_count != nil && (fetched_count.nil? || fetched_count < @prev_fetched_count)
        regressions << "fetched_count_down"
        kv_bag[:prev_fetched_count] = @prev_fetched_count.dup
        kv_bag[:new_fetched_count] = fetched_count
      end
      @prev_fetched_count = fetched_count
    end

    unless regressions.empty?
      @progress_saver.emit_telemetry(regressions.join(","), kv_bag)
    end
  end
end