def monotonic_now
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

def is_str_nil_or_empty(str)
  str.nil? || str.empty?
end

def print_nice_error(error)
  lines = [error.to_s]
  loop do
    if error.backtrace
      lines << "---"
      error.backtrace.each do |line|
        lines << line
      end
    end

    if error.cause
      error = error.cause
    else
      break
    end
  end

  lines
end