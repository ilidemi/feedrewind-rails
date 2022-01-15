create type pattern as enum (
    'archives',
    'paged',
    'archives2level',
    'archives4level', -- deprecated
    'paged_next',
    'paged_last',
    'paged_second_last', -- deprecated
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
    'archives2level_shuffled_almost', -- deprecated
    'archives_shuffled_scoped',
    'archives_categories_shuffled', -- deprecated
    'paged_next_scoped',
    'feed', -- deprecated
    'archives_categories_almost',
    'archives_shuffled_almost',
    'long_feed',
    'archives_almost_feed', -- deprecated
    'archives_feed_almost',
    'archives_long_feed',
    'tumblr'
    );

create table historical_ground_truth
(
    start_link_id              integer references start_links on delete cascade primary key,
    pattern                    pattern not null,
    entries_count              integer not null,
    main_page_canonical_url    text    not null,
    oldest_entry_canonical_url text    not null,
    titles                     text[],
    links                      text[]
);
