create table mock_permanent_errors
(
    id            serial primary key,
    canonical_url text                                             not null,
    fetch_url     text                                             not null,
    fetch_time    timestamp                                        not null,
    start_link_id integer references start_links on delete cascade not null,
    code          text                                             not null,
    unique (fetch_url, start_link_id)
);