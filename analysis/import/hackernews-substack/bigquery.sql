select url, score from `bigquery-public-data.hacker_news.full`
where url is not null
  and url like '%/p/%'
  and extract(year from timestamp) >= 2020
  and score > 50
  and url not like '%substack.com%'
order by score desc
