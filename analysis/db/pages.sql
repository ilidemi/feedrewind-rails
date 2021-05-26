create table pages
(
    canonical_url text primary key,
    fetch_url     text                           not null,
    content_type  text                           not null,
    start_link_id integer references start_links not null,
    content       text
);