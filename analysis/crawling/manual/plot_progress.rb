require 'gnuplot'

data = {}
max = nil
File.open("../notes/progress.txt") do |progress_f|
  current_symbol = nil
  current_data = []
  progress_f.each do |line|
    unless line.include?(":")
      data[current_symbol] = current_data.transpose if current_symbol
      current_symbol = line[0].upcase
      current_data = []
    end

    date, count_s = line.split(": ")
    count = count_s.to_i
    max = count if date == 'max'
    next unless date.include?("/")

    current_data << [date, count]
  end
  data[current_symbol] = current_data.transpose
end

result = Gnuplot.open do |gp|
  Gnuplot::Plot.new(gp) do |plot|
    plot.settings << [:set, 'terminal', 'dumb']
    plot.settings << [:set, 'xdata', 'time']
    plot.settings << [:set, 'timefmt', "'%m/%d'"]
    plot.settings << [:set, 'yrange', "[0:#{max}]"]
    data.each do |symbol, symbol_data|
      dataset = Gnuplot::DataSet.new(symbol_data)
      dataset.title = ""
      dataset.with = "points pt '#{symbol}'"
      dataset.using = "1:2"
      plot.data << dataset
    end
  end
end

puts result
