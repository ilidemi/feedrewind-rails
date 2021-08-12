require 'time'

def try_extract_element_date(element, guess_year)
  if element.name == "time"
    if element.attributes.key?("datetime")
      date = try_extract_text_date(element.attributes["datetime"].value, guess_year)
      return { date: date, source: :time } if date
    end
    return nil
  end

  if element.text?
    date = try_extract_text_date(element.content, guess_year)
    return { date: date, source: :text } if date
  end

  nil
end

def try_extract_text_date(text, guess_year)
  text = text.strip
  return nil if text.empty?

  # Assuming dates can't get longer than that
  # Longest seen was "(September 12 2005, last updated September 17 2005)"
  # at https://tratt.net/laurie/blog/archive.html
  return nil if text.length > 60

  return nil if text.match?(/\d\/\d/) # Can't distinguish between MM/DD/YY and DD/MM/YY
  return nil unless text.match?(/\d/) # Dates must have numbers

  yyyy_mm_dd_match = text.match(/(?:[^\d]|^)(\d\d\d\d)-(\d\d)-(\d\d)(?:[^\d]|$)/)

  if yyyy_mm_dd_match
    begin
      date = Date.new(yyyy_mm_dd_match[1].to_i, yyyy_mm_dd_match[2].to_i, yyyy_mm_dd_match[3].to_i)
      return date
    rescue
    end
  end

  begin
    date_hash = Date._parse(text)
    return nil unless date_hash && date_hash.key?(:mon) && date_hash.key?(:mday)

    text_numbers = text.scan(/\d+/)

    if date_hash.key?(:year)
      year_string = date_hash[:year].to_s
      return nil unless text_numbers.any? { |number| [year_string, year_string[-2..]].include?(number) }
    elsif guess_year
      # Special treatment only for missing year but not month or day
      date_hash[:year] = Date.today.year
    else
      return nil
    end

    day_string = date_hash[:mday].to_s
    day_string_padded = day_string.rjust(2, '0')
    return nil unless text_numbers.any? { |number| [day_string, day_string_padded].include?(number) }

    date = Date.new(date_hash[:year], date_hash[:mon], date_hash[:mday])
    return date
  rescue
    return nil
  end
end