require 'time'

def try_extract_date(element)
  if element.name == "time"
    if element.attributes.key?("datetime")
      date = try_extract_date_from_text(element.attributes["datetime"].value)
      return { date: date, source: :time } if date
    end
    return nil
  end

  if element.text?
    date = try_extract_date_from_text(element.content)
    return { date: date, source: :text } if date
    return nil
  end

  nil
end

def try_extract_date_from_text(text)
  text = text.strip
  return nil if text.empty?

  # Assuming dates can't get longer than that
  # Longest seen was "(September 12 2005, last updated September 17 2005)"
  # at https://tratt.net/laurie/blog/archive.html
  return nil if text.length > 60

  return nil if text.include?("/") # Can't distinguish between MM/DD/YY and DD/MM/YY
  return nil unless text.match?(/\d/) # Dates must have numbers

  begin
    date_hash = Date._parse(text)
    return nil unless date_hash && date_hash.key?(:year) && date_hash.key?(:mon) && date_hash.key?(:mday)

    text_numbers = text.scan(/\d+/)
    year_string = date_hash[:year].to_s
    day_string = date_hash[:mday].to_s
    day_string_padded = day_string.rjust(2, '0')
    return nil unless text_numbers.any? { |number| [year_string, year_string[-2..]].include?(number) }
    return nil unless text_numbers.any? { |number| [day_string, day_string_padded].include?(number) }

    date = Date.new(date_hash[:year], date_hash[:mon], date_hash[:mday])
    return date
  rescue
    return nil
  end
end