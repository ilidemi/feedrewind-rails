create table historical
(
    start_link_id              integer references start_links on delete cascade primary key,
    pattern                    pattern not null,
    entries_count              integer not null,
    blog_canonical_url         text    not null,
    main_page_canonical_url    text    not null,
    oldest_entry_canonical_url text    not null,
    titles                     text[],
    links                      text[]
);