create table mock_pages
(
    id                serial primary key,
    canonical_url     text                                             not null,
    fetch_url         text                                             not null,
    fetch_time        timestamp                                        not null,
    content_type      text,
    start_link_id     integer references start_links on delete cascade not null,
    content           bytea,
    is_from_puppeteer boolean                                          not null,
    unique (fetch_url, start_link_id, is_from_puppeteer)
);