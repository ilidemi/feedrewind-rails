def to_column_names(result_columns)
  result_columns.map { |column| column[0].to_s.gsub("_", " ") }
end

class RunResult
  def initialize(result_columns)
    @result_columns = result_columns
    @result_columns.each do |column|
      [column[0], "#{column[0]}_status"].each do |attr_name|
        instance_variable_set("@#{attr_name}", nil)
        self.class.send(:attr_writer, attr_name)
      end
    end
  end

  def column_values
    @result_columns.map { |column| instance_variable_get("@#{column[0]}") }
  end

  def column_statuses
    @result_columns.map do |column|
      manual_status = instance_variable_get("@#{column[0]}_status")
      if manual_status
        next manual_status
      end

      if column[1] == :neutral
        :neutral
      elsif column[1] == :neutral_present
        instance_variable_get("@#{column[0]}") ? :neutral : :failure
      elsif column[1] == :boolean
        instance_variable_get("@#{column[0]}") ? :success : :failure
      else
        raise "Unknown column status symbol: #{column[1]}"
      end
    end
  end
end

class RunError < StandardError
  def initialize(message, result)
    @result = result
    super(message)
  end

  attr_reader :result
end