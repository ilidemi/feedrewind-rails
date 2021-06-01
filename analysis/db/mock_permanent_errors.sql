create table mock_permanent_errors
(
    canonical_url text primary key,
    fetch_url     text                           not null,
    fetch_time    timestamp                      not null,
    start_link_id integer references start_links not null,
    code          text                           not null
);