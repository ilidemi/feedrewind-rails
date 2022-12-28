class MockProgressSaver
  def initialize(logger)
    @logger = logger
  end

  def save_status_and_count(status_str, count)
    @logger.info("Progress save status: #{status_str} count: #{count || "nil"}")
    @status_str = status_str
    @count = count
  end

  def save_status(status_str)
    @logger.info("Progress save status: #{status_str}")
    @status_str = status_str
  end

  def save_count(count)
    @logger.info("Progress save count: #{count || "nil"}")
    @count = count
  end

  def emit_telemetry(regressions, kv_bag)
    @logger.info("Progress regression: #{regressions} #{kv_bag}")
  end

  attr_reader :status_str, :count
end
