create table permanent_errors
(
    id            serial primary key,
    canonical_url text                                             not null,
    fetch_url     text                                             not null,
    start_link_id integer references start_links on delete cascade not null,
    code          text                                             not null,
    unique (canonical_url, start_link_id)
);