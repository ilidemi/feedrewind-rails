select up_url, sum_score, count
from (
         select max(up_url)                              as up_url,
                regexp_replace(up_url, '^https?://', '') as up_curl,
                sum(score)                               as sum_score,
                count(*)                                 as count
         from (
                  select regexp_replace(url, '(/[0-9]+)*/[^/]+/?$', '') as up_url, score
                  from ` bigquery- public - data.hacker_news.full `
                  where url is not null
                    and url not like '%jobs'
                    and url not like '%careers'
                    and ( -- not top level
                      array_length(split(url
                      , '/'))
                      > 4
                     or (array_length(split(url
                      , '/')) = 4
                    and not ends_with(url
                      , '/'))
                      )
              )
         group by up_curl
     )
--where sum_score > 10
order by sum_score desc
