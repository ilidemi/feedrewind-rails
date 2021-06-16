require 'cgi'
require 'fileutils'
require 'tmpdir'

def output_report(filename, result_column_names, results, expected_total)
  success_count = 0
  failure_count = 0
  bad_failure_count = 0
  evaluated_results = []

  results.each do |result|
    if result[1].nil?
      bad_failure_count += 1
      evaluated_results << result
    else
      column_values = result[1].column_values
      column_statuses = result[1].column_statuses
      if column_statuses.include?(:failure)
        failure_count += 1
      else
        success_count += 1
      end
      evaluated_results << [result[0], { values: column_values, statuses: column_statuses }, result[2]]
    end
  end

  status_keys = { success: -1, neutral: 0, failure: 1 }
  sorted_results = evaluated_results.sort_by do |result|
    [
      result[1].nil? ? [1] * result_column_names.length : result[1][:statuses].map { |status| status_keys[status] },
      result[2] || "",
      result[0]
    ]
  end

  if !sorted_results.empty?
    column_counters = (0...result_column_names.length).map do |index|
      column_status_counts = sorted_results
        .map { |result| result[1][:statuses][index] }
        .each_with_object(Hash.new(0)) { |word, counts| counts[word] += 1 }
      if column_status_counts.include?(:neutral) && column_status_counts.length == 1
        []
      elsif column_status_counts.include?(:neutral)
        [
          column_status_counts[:success] || 0,
          column_status_counts[:neutral] || 0,
          column_status_counts[:failure] || 0
        ]
      else
        [
          column_status_counts[:success] || 0,
          column_status_counts[:failure] || 0
        ]
      end
    end
  else
    column_counters = nil
  end

  styles = {
    neutral: '',
    success: " style=\"background: lightgreen;\"",
    failure: " style=\"background: lightcoral;\""
  }

  temp_filename = File.join(Dir.tmpdir, "rss_catchup_report.html")
  File.open(temp_filename, 'w') do |report_file|
    report_file.write("<html>\n")
    report_file.write("<head>\n")
    report_file.write("<title>Report</title>\n")
    report_file.write("<style>table, th, td { border: 1px solid black; border-collapse: collapse; }</style>\n")
    report_file.write("</head>\n")
    report_file.write("<body>\n")

    report_file.write("Processed: #{sorted_results.length}/#{expected_total}\n")
    report_file.write("<br>\n")

    report_file.write("Success: #{success_count} Failure: #{failure_count} Bad failure: #{bad_failure_count}\n")
    report_file.write("<br>\n")

    report_file.write("Weissman score: #{sorted_results.empty? ? 'N/A' : (success_count * 100 / sorted_results.length).to_i}%\n")
    report_file.write("<br>\n")

    report_file.write("<table>\n<tr>")
    report_file.write("<th>id</th>")
    result_column_names.each_with_index do |column_name, index|
      if column_counters
        column_counter = column_counters[index]
        if column_counter.length == 3
          column_counter_str = "<br>"
          column_counter_str += "<span style=\"color: green;\">#{column_counter[0]}</span>"
          column_counter_str += " / #{column_counter[1]} / "
          column_counter_str += "<span style=\"color: red;\">#{column_counter[2]}</span>"
        elsif column_counter.length == 2
          column_counter_str = "<br>"
          column_counter_str += "<span style=\"color: green;\">#{column_counter[0]}</span> / "
          column_counter_str += "<span style=\"color: red;\">#{column_counter[1]}</span>"
        else
          column_counter_str = ''
        end
      else
        column_counter_str = ''
      end
      report_file.write("<th>#{column_name}#{column_counter_str}</th>")
    end
    report_file.write("<th>error</th>")
    report_file.write("</tr>\n")

    sorted_results.each do |result|
      report_file.write("<tr>")
      report_file.write("<td>#{result[0]}</td>")

      if result[1].nil?
        result_column_names.length.times do
          report_file.write("<td></td>")
        end
      else
        result[1][:values].each_with_index do |value, index|
          status = result[1][:statuses][index]
          report_file.write("<td#{styles[status]}>#{value}</td>")
        end
      end

      if result[2].nil?
        report_file.write("<td></td>")
      else
        error_html = CGI::escapeHTML(result[2]).gsub("\n", "<br>")
        report_file.write("<td#{styles[:failure]}>#{error_html}</td>")
      end
      report_file.write("</tr>\n")
    end
    report_file.write("</table>\n")
    report_file.write('</body></html>')
  end

  if File.exist?(filename)
    File.delete(filename)
  end
  FileUtils.mv(temp_filename, filename)
end
