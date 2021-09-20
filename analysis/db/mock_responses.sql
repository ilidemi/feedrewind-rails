create table mock_responses
(
    id            serial primary key,
    start_link_id integer references start_links on delete cascade not null,
    fetch_url     text                                             not null,
    code          text                                             not null,
    content_type  text,
    location      text,
    body          bytea,
    unique (start_link_id, fetch_url)
);