-- delete
delete from historical_ground_truth where start_link_id = 0;

-- copy
insert into historical_ground_truth select * from historical where start_link_id = 0;

-- insert
insert into historical_ground_truth (start_link_id, pattern, entries_count, main_page_canonical_url, oldest_entry_canonical_url) values (