create table known_failures
(
    start_link_id integer references start_links primary key,
    reason        text not null
);
