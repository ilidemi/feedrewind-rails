create table mock_puppeteer_pages
(
    id            serial primary key,
    start_link_id integer references start_links on delete cascade,
    fetch_url     text  not null,
    body          bytea not null
);