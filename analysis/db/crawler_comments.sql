create table crawler_comments
(
    start_link_id integer references start_links primary key,
    comment       text not null
);
