create type pattern as enum (
    'archives',
    'paged',
    'archives2level',
    'archives4level',
    'paged_next',
    'paged_last',
    'paged_second_last',
    'paged_month',
    'archives_almost',
    'archives_shuffled_2xpaths',
    'archives_2xpaths',
    'paged_mid_next',
    'paged_next_almost',
    'archives_shuffled',
    'archives_categories',
    'chained',
    'paged_last_reversed',
    'archives2level_shuffled_almost',
    'archives_shuffled_scoped',
    'archives_categories_shuffled',
    'paged_next_scoped',
    'feed',
    'long_feed'
    );

create table historical_ground_truth
(
    start_link_id              integer references start_links on delete cascade primary key,
    pattern                    pattern not null,
    entries_count              integer not null,
    main_page_canonical_url    text    not null,
    oldest_entry_canonical_url text    not null,
    last_page_canonical_url    text
);
