def monotonic_now
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

def print_nice_error(io, error)
  io.puts(error.to_s)
  loop do
    if error.backtrace
      io.puts("---")
      error.backtrace.each do |line|
        io.puts(line)
      end
    end

    if error.cause
      error = error.cause
    else
      break
    end
  end
end