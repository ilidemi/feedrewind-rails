create table feeds
(
    start_link_id integer references start_links on delete cascade primary key,
    page_id       integer references pages not null
);