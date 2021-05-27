create table notfounds
(
    canonical_url text primary key,
    start_link_id integer references start_links not null
);