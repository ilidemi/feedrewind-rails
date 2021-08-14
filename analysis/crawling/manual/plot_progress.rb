require 'date'
require 'gnuplot'

data = {}
max = nil
max_date = Date.new
year = Date.today.year
File.open("../notes/progress.txt") do |progress_f|
  current_symbol = nil
  current_data = []
  progress_f.each do |line|
    unless line.include?(":")
      data[current_symbol] = current_data.transpose if current_symbol
      current_symbol = line[0].upcase
      current_data = []
    end

    date_s, count_s = line.split(": ")
    count = count_s.to_i
    max = count if date_s == 'max'
    next unless date_s.include?("/")

    month, day = date_s.split("/").map(&:to_i)
    date = Date.new(year, month, day)
    max_date = [date, max_date].max

    current_data << [date_s, count]
  end
  data[current_symbol] = current_data.transpose
end

max_date += 1

result = Gnuplot.open do |gp|
  Gnuplot::Plot.new(gp) do |plot|
    plot.settings << [:set, 'terminal', 'dumb']
    plot.settings << [:set, 'xdata', 'time']
    plot.settings << [:set, 'timefmt', "'%m/%d'"]
    plot.settings << [:set, 'xrange', "[:'#{max_date.month}/#{max_date.day}']"]
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
