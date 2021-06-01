create table mock_pages
(
    canonical_url text primary key,
    fetch_url     text                           not null,
    fetch_time    timestamp                      not null,
    content_type  text                           not null,
    start_link_id integer references start_links not null,
    content       text
);