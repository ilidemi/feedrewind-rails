create table feeds
(
    start_link_id integer references start_links primary key,
    canonical_url text references pages not null
);