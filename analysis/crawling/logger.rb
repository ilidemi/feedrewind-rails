class MyLogger
  def initialize(log_file)
    @log_file = log_file
  end

  def log(message)
    @log_file.write("#{Time.now} #{message}\n")
    @log_file.flush
    nil
  end
end