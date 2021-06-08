select start_link_id, count(id) from mock_pages where start_link_id not in (select start_link_id from feeds) and content is null group by start_link_id order by count desc;

delete from mock_pages where start_link_id not in (select start_link_id from feeds) and content is null;