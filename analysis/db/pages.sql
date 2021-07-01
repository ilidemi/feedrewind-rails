create table pages
(
    id            serial primary key,
    canonical_url text                                             not null,
    fetch_url     text                                             not null,
    content_type  text,
    start_link_id integer references start_links on delete cascade not null,
    content       bytea,
    unique (canonical_url, start_link_id)
);