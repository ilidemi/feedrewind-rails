create table redirects
(
    id             serial primary key,
    from_fetch_url text                                             not null,
    to_fetch_url   text                                             not null,
    start_link_id  integer references start_links on delete cascade not null,
    unique (from_fetch_url, start_link_id)
);