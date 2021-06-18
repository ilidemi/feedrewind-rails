create type severity as enum ('discard', 'fail', 'neutral');

create table known_issues
(
    start_link_id integer references start_links primary key,
    severity      severity not null,
    issue         text     not null
);
