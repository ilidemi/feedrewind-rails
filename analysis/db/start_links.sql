create table start_links
(
    id        serial primary key,
    source_id integer references sources not null,
    url       text                       not null,
    comment   text
);