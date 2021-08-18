create type start_link_source as enum ('my', 'blaggregator', 'blaggregator2', 'random', 'blogroll');

create table start_links
(
    id      serial primary key,
    source  start_link_source not null,
    url     text,
    rss_url text,
    comment text
);