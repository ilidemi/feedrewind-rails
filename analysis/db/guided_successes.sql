create table guided_successes
(
    start_link_id integer references start_links on delete cascade primary key,
    timestamp     timestamp not null
);