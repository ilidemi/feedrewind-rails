create table mock_pages
(
    id            serial primary key,
    canonical_url text                           not null,
    fetch_url     text                           not null,
    fetch_time    timestamp                      not null,
    content_type  text                           not null,
    start_link_id integer references start_links not null,
    content       text,
    unique (fetch_url, start_link_id)
);