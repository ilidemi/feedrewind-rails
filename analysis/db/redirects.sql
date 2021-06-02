create table redirects
(
    from_fetch_url text primary key,
    to_fetch_url   text                           not null,
    start_link_id  integer references start_links not null
);