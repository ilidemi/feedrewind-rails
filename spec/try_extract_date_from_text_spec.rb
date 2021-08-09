require_relative '../analysis/crawling/date_extraction'

passing_dates = [
  ["-  1 February 2015", 2015, 2, 1],
  ["- April 18, 2021", 2021, 4, 18],
  [", April 27, 2014", 2014, 4, 27],
  ["(04-05-2020)", 2020, 5, 4],
  ["(December 10 2005)", 2005, 12, 10],
  ["(February 8 2012, last updated February 7 2013)", 2012, 2, 8],
  ["(May 11 2007)", 2007, 5, 11],
  ["01 Dec 2015", 2015, 12, 1],
  ["01 November 2016", 2016, 11, 1],
  ["04 Nov 2019 »", 2019, 11, 4],
  ["05 October 2018 at 09:21 UTC", 2018, 10, 5],
  ["07 JAN 2017", 2017, 1, 7],
  ["07 Mar 2011:", 2011, 3, 7],
  ["1 Jul 2018", 2018, 7, 1],
  ["11 Apr, 2021", 2021, 4, 11],
  ["2010-11-06", 2010, 11, 6],
  ["2011-05-21 | ", 2011, 5, 21],
  ["2013 Aug 14 -", 2013, 8, 14],
  ["2013 August 24", 2013, 8, 24],
  ["2014-11-12 04:13", 2014, 11, 12],
  ["2014-11-14", 2014, 11, 14],
  ["2020-02-06:", 2020, 2, 6],
  ["April 21, 2021", 2021, 4, 21],
  ["By Michael Altfield, on April 15th, 2020", 2020, 4, 15],
  ["Dec 10 2020", 2020, 12, 10],
  ["Dec 15 '20", 2020, 12, 15],
  ["December 17th, 2010 | Tags:", 2010, 12, 17],
  ["Disabling Emojis In WordPress — November 28, 2016", 2016, 11, 28],
  ["entry was around 2009-04-11.", 2009, 4, 11],
  ["Friday, 6 November 2015", 2015, 11, 6],
  ["Jan 13, 2018				•", 2018, 1, 13],
  ["May 31, 2020: A toy compiler from scratch", 2020, 5, 31],
  ["Never Graduate Week 2018! — May 16, 2018", 2018, 5, 16],
  ["on 2020-10-09", 2020, 10, 9],
  ["Posted by ＳｔｕｆｆｏｎｍｙＭｉｎｄ on February 25, 2021", 2021, 2, 25],
  ["Things I learnt 23 June 2019", 2019, 6, 23],
  ["Tue 18 November 2014", 2014, 11, 18],
  ["2021-07-16 17:00:00+00:00", 2021, 7, 16],
  ["/ Dec 14, 2018", 2018, 12, 14]
]

passing_dates_with_guessed_year = [
  ["Jan 23", 1, 23],
  ["July 5", 7, 5]
]

failing_dates = [
  "",
  "   \n\t",
  "asdf",
  ".",
  "A quick brown fox is jumping over the lazy dog. It is jumping and jumping. Merry Christmas Dec 25, 2019",
  "4/5/2020",
  "4/16/2020",
  "16/4/2020",
  "'11'",
  "(21 comments)",
  ", April 2019",
  "(Dec '17)",
  "#21 -",
  "21",
  "21 Comments",
  "21 minutes",
  "And how this can help you think about 2021.",
  "hg advent -m '02: extensions'",
  "Zig: December 2017 in Review",
  "Source: Posted on twitter by user @mrdrozdov in Jan 2020."
]

RSpec.describe "try_extract_date" do
  passing_dates.each do |text, year, month, day|
    it text do
      date = try_extract_text_date(text, false)
      expect(date.year).to eq year
      expect(date.month).to eq month
      expect(date.day).to eq day
    end
  end

  passing_dates_with_guessed_year.each do |text, month, day|
    it text do
      date = try_extract_text_date(text, true)
      expect(date.month).to eq month
      expect(date.day).to eq day
    end
  end

  failing_dates.each do |text|
    it text do
      date = try_extract_text_date(text, true)
      expect(date).to be_nil
    end
  end
end