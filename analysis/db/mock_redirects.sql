create table mock_redirects
(
    from_canonical_url text primary key,
    to_canonical_url   text                           not null,
    to_fetch_url       text                           not null,
    fetch_time         timestamp                      not null,
    start_link_id      integer references start_links not null
);