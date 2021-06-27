create table successes
(
    start_link_id integer references start_links primary key,
    timestamp     timestamp not null
);