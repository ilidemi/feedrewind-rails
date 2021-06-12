create table historical
(
    start_link_id              integer references start_links primary key,
    pattern                    pattern not null,
    entries_count              integer not null,
    main_page_canonical_url    text    not null,
    oldest_entry_canonical_url text    not null
);