create table feeds
(
    start_link_id integer references start_links primary key,
    page_id       integer references pages not null
);