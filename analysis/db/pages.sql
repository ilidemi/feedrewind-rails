create table pages
(
    id            serial primary key,
    canonical_url text                           not null,
    fetch_url     text                           not null,
    content_type  text                           not null,
    start_link_id integer references start_links not null,
    content       text,
    unique (canonical_url, start_link_id)
);