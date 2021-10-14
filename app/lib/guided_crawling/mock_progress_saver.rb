class MockProgressSaver
  def save_status(status_str)
    @status_str = status_str
  end

  def save_count(count)
    @count = count
  end

  attr_reader :status_str, :count
end
