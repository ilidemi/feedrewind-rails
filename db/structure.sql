SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: blog_crawl_vote_value; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.blog_crawl_vote_value AS ENUM (
    'confirmed',
    'looks_wrong'
);


--
-- Name: blog_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.blog_status AS ENUM (
    'crawl_in_progress',
    'crawl_failed',
    'crawled_voting',
    'crawled_confirmed',
    'crawled_looks_wrong',
    'manually_inserted',
    'update_from_feed_failed'
);


--
-- Name: blog_update_action; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.blog_update_action AS ENUM (
    'recrawl',
    'update_from_feed_or_fail',
    'no_op',
    'fail'
);


--
-- Name: day_of_week; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.day_of_week AS ENUM (
    'mon',
    'tue',
    'wed',
    'thu',
    'fri',
    'sat',
    'sun'
);


--
-- Name: old_blog_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.old_blog_status AS ENUM (
    'crawl_in_progress',
    'crawled',
    'confirmed',
    'live',
    'crawl_failed',
    'crawled_looks_wrong'
);


--
-- Name: post_delivery_channel; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.post_delivery_channel AS ENUM (
    'single_feed',
    'multiple_feeds',
    'email'
);


--
-- Name: post_email_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.post_email_status AS ENUM (
    'sent',
    'skipped',
    'pending'
);


--
-- Name: subscription_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.subscription_status AS ENUM (
    'waiting_for_blog',
    'setup',
    'live'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: blog_canonical_equality_configs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blog_canonical_equality_configs (
    blog_id bigint NOT NULL,
    same_hosts text[],
    expect_tumblr_paths boolean NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: blog_crawl_client_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blog_crawl_client_tokens (
    value character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    blog_id bigint NOT NULL
);


--
-- Name: blog_crawl_progresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blog_crawl_progresses (
    progress character varying,
    count integer,
    epoch integer NOT NULL,
    epoch_times character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    blog_id bigint NOT NULL
);


--
-- Name: blog_crawl_votes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blog_crawl_votes (
    id bigint NOT NULL,
    blog_id bigint NOT NULL,
    value public.blog_crawl_vote_value NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint
);


--
-- Name: blog_crawl_votes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.blog_crawl_votes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: blog_crawl_votes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.blog_crawl_votes_id_seq OWNED BY public.blog_crawl_votes.id;


--
-- Name: blog_discarded_feed_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blog_discarded_feed_entries (
    id bigint NOT NULL,
    blog_id bigint NOT NULL,
    url character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: blog_discarded_feed_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.blog_discarded_feed_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: blog_discarded_feed_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.blog_discarded_feed_entries_id_seq OWNED BY public.blog_discarded_feed_entries.id;


--
-- Name: blog_post_locks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blog_post_locks (
    blog_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: blog_posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blog_posts (
    id bigint NOT NULL,
    blog_id bigint NOT NULL,
    index integer NOT NULL,
    url character varying NOT NULL,
    title character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: blog_posts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.blog_posts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: blog_posts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.blog_posts_id_seq OWNED BY public.blog_posts.id;


--
-- Name: blogs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blogs (
    id bigint NOT NULL,
    name character varying NOT NULL,
    feed_url character varying NOT NULL,
    status public.blog_status NOT NULL,
    status_updated_at timestamp without time zone NOT NULL,
    version integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    update_action public.blog_update_action NOT NULL,
    url character varying
);


--
-- Name: delayed_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.delayed_jobs (
    id bigint NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    handler text NOT NULL,
    last_error text,
    run_at timestamp without time zone,
    locked_at timestamp without time zone,
    failed_at timestamp without time zone,
    locked_by character varying,
    queue character varying,
    created_at timestamp(6) without time zone,
    updated_at timestamp(6) without time zone
);


--
-- Name: delayed_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.delayed_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: delayed_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.delayed_jobs_id_seq OWNED BY public.delayed_jobs.id;


--
-- Name: schedules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schedules (
    id bigint NOT NULL,
    day_of_week public.day_of_week NOT NULL,
    count integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    subscription_id bigint NOT NULL
);


--
-- Name: schedules_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.schedules_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: schedules_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.schedules_id_seq OWNED BY public.schedules.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: start_feeds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.start_feeds (
    id bigint NOT NULL,
    content bytea,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    url text NOT NULL,
    final_url text,
    title text NOT NULL,
    start_page_id integer
);


--
-- Name: start_pages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.start_pages (
    id bigint NOT NULL,
    content bytea NOT NULL,
    url text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    final_url text NOT NULL
);


--
-- Name: start_pages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.start_pages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: start_pages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.start_pages_id_seq OWNED BY public.start_pages.id;


--
-- Name: subscription_posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscription_posts (
    id bigint NOT NULL,
    blog_post_id bigint NOT NULL,
    subscription_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    published_at timestamp without time zone,
    published_at_local_date character varying,
    email_status public.post_email_status
);


--
-- Name: subscription_posts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.subscription_posts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subscription_posts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.subscription_posts_id_seq OWNED BY public.subscription_posts.id;


--
-- Name: subscription_rsses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscription_rsses (
    id bigint NOT NULL,
    body text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    subscription_id bigint NOT NULL
);


--
-- Name: subscription_rsses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.subscription_rsses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subscription_rsses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.subscription_rsses_id_seq OWNED BY public.subscription_rsses.id;


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscriptions (
    id bigint NOT NULL,
    blog_id bigint NOT NULL,
    name character varying NOT NULL,
    status public.subscription_status NOT NULL,
    is_paused boolean,
    is_added_past_midnight boolean,
    discarded_at timestamp without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    version integer NOT NULL,
    finished_setup_at timestamp without time zone,
    final_item_published_at timestamp without time zone,
    user_id bigint
);


--
-- Name: test_singletons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.test_singletons (
    key text NOT NULL,
    value text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: user_rsses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_rsses (
    body text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint NOT NULL
);


--
-- Name: user_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_settings (
    user_id bigint NOT NULL,
    timezone character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    version integer NOT NULL,
    delivery_channel public.post_delivery_channel NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    email character varying,
    password_digest character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    auth_token character varying,
    id bigint NOT NULL
);


--
-- Name: blog_crawl_votes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blog_crawl_votes ALTER COLUMN id SET DEFAULT nextval('public.blog_crawl_votes_id_seq'::regclass);


--
-- Name: blog_discarded_feed_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blog_discarded_feed_entries ALTER COLUMN id SET DEFAULT nextval('public.blog_discarded_feed_entries_id_seq'::regclass);


--
-- Name: blog_posts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blog_posts ALTER COLUMN id SET DEFAULT nextval('public.blog_posts_id_seq'::regclass);


--
-- Name: delayed_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delayed_jobs ALTER COLUMN id SET DEFAULT nextval('public.delayed_jobs_id_seq'::regclass);


--
-- Name: schedules id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedules ALTER COLUMN id SET DEFAULT nextval('public.schedules_id_seq'::regclass);


--
-- Name: start_pages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.start_pages ALTER COLUMN id SET DEFAULT nextval('public.start_pages_id_seq'::regclass);


--
-- Name: subscription_posts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_posts ALTER COLUMN id SET DEFAULT nextval('public.subscription_posts_id_seq'::regclass);


--
-- Name: subscription_rsses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_rsses ALTER COLUMN id SET DEFAULT nextval('public.subscription_rsses_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: blog_canonical_equality_configs blog_canonical_equality_configs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blog_canonical_equality_configs
    ADD CONSTRAINT blog_canonical_equality_configs_pkey PRIMARY KEY (blog_id);


--
-- Name: blog_crawl_client_tokens blog_crawl_client_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blog_crawl_client_tokens
    ADD CONSTRAINT blog_crawl_client_tokens_pkey PRIMARY KEY (blog_id);


--
-- Name: blog_crawl_progresses blog_crawl_progresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blog_crawl_progresses
    ADD CONSTRAINT blog_crawl_progresses_pkey PRIMARY KEY (blog_id);


--
-- Name: blog_crawl_votes blog_crawl_votes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blog_crawl_votes
    ADD CONSTRAINT blog_crawl_votes_pkey PRIMARY KEY (id);


--
-- Name: blog_discarded_feed_entries blog_discarded_feed_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blog_discarded_feed_entries
    ADD CONSTRAINT blog_discarded_feed_entries_pkey PRIMARY KEY (id);


--
-- Name: blog_post_locks blog_post_locks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blog_post_locks
    ADD CONSTRAINT blog_post_locks_pkey PRIMARY KEY (blog_id);


--
-- Name: blog_posts blog_posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blog_posts
    ADD CONSTRAINT blog_posts_pkey PRIMARY KEY (id);


--
-- Name: blogs blogs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blogs
    ADD CONSTRAINT blogs_pkey PRIMARY KEY (id);


--
-- Name: delayed_jobs delayed_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delayed_jobs
    ADD CONSTRAINT delayed_jobs_pkey PRIMARY KEY (id);


--
-- Name: schedules schedules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedules
    ADD CONSTRAINT schedules_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: start_feeds start_feeds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.start_feeds
    ADD CONSTRAINT start_feeds_pkey PRIMARY KEY (id);


--
-- Name: start_pages start_pages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.start_pages
    ADD CONSTRAINT start_pages_pkey PRIMARY KEY (id);


--
-- Name: subscription_posts subscription_posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_posts
    ADD CONSTRAINT subscription_posts_pkey PRIMARY KEY (id);


--
-- Name: subscription_rsses subscription_rsses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_rsses
    ADD CONSTRAINT subscription_rsses_pkey PRIMARY KEY (id);


--
-- Name: subscriptions subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);


--
-- Name: test_singletons test_singletons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_singletons
    ADD CONSTRAINT test_singletons_pkey PRIMARY KEY (key);


--
-- Name: user_rsses user_rsses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_rsses
    ADD CONSTRAINT user_rsses_pkey PRIMARY KEY (user_id);


--
-- Name: user_settings user_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_settings
    ADD CONSTRAINT user_settings_pkey PRIMARY KEY (user_id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: delayed_jobs_priority; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX delayed_jobs_priority ON public.delayed_jobs USING btree (priority, run_at);


--
-- Name: index_blogs_on_feed_url_and_version; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_blogs_on_feed_url_and_version ON public.blogs USING btree (feed_url, version);


--
-- Name: index_start_feeds_on_start_page_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_start_feeds_on_start_page_id ON public.start_feeds USING btree (start_page_id);


--
-- Name: index_users_on_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_id ON public.users USING btree (id);


--
-- Name: user_rsses fk_rails_17396fc3a7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_rsses
    ADD CONSTRAINT fk_rails_17396fc3a7 FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE;


--
-- Name: subscriptions fk_rails_416412a06b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT fk_rails_416412a06b FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE;


--
-- Name: subscription_rsses fk_rails_647dccf03a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_rsses
    ADD CONSTRAINT fk_rails_647dccf03a FOREIGN KEY (subscription_id) REFERENCES public.subscriptions(id);


--
-- Name: blog_crawl_votes fk_rails_6d5d61b810; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blog_crawl_votes
    ADD CONSTRAINT fk_rails_6d5d61b810 FOREIGN KEY (blog_id) REFERENCES public.blogs(id);


--
-- Name: blog_discarded_feed_entries fk_rails_76729800cc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blog_discarded_feed_entries
    ADD CONSTRAINT fk_rails_76729800cc FOREIGN KEY (blog_id) REFERENCES public.blogs(id);


--
-- Name: blog_canonical_equality_configs fk_rails_9b3fd3910a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blog_canonical_equality_configs
    ADD CONSTRAINT fk_rails_9b3fd3910a FOREIGN KEY (blog_id) REFERENCES public.blogs(id);


--
-- Name: blog_posts fk_rails_9d677c923b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blog_posts
    ADD CONSTRAINT fk_rails_9d677c923b FOREIGN KEY (blog_id) REFERENCES public.blogs(id);


--
-- Name: schedules fk_rails_b2b9b40998; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedules
    ADD CONSTRAINT fk_rails_b2b9b40998 FOREIGN KEY (subscription_id) REFERENCES public.subscriptions(id);


--
-- Name: subscription_posts fk_rails_b5e611fa3d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_posts
    ADD CONSTRAINT fk_rails_b5e611fa3d FOREIGN KEY (subscription_id) REFERENCES public.subscriptions(id);


--
-- Name: blog_crawl_client_tokens fk_rails_blogs; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blog_crawl_client_tokens
    ADD CONSTRAINT fk_rails_blogs FOREIGN KEY (blog_id) REFERENCES public.blogs(id);


--
-- Name: blog_crawl_progresses fk_rails_blogs; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blog_crawl_progresses
    ADD CONSTRAINT fk_rails_blogs FOREIGN KEY (blog_id) REFERENCES public.blogs(id);


--
-- Name: blog_post_locks fk_rails_c1a166e65f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blog_post_locks
    ADD CONSTRAINT fk_rails_c1a166e65f FOREIGN KEY (blog_id) REFERENCES public.blogs(id);


--
-- Name: subscriptions fk_rails_c6353e971b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT fk_rails_c6353e971b FOREIGN KEY (blog_id) REFERENCES public.blogs(id);


--
-- Name: user_settings fk_rails_d1371c6356; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_settings
    ADD CONSTRAINT fk_rails_d1371c6356 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: subscription_posts fk_rails_d857bf4496; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_posts
    ADD CONSTRAINT fk_rails_d857bf4496 FOREIGN KEY (blog_post_id) REFERENCES public.blog_posts(id);


--
-- Name: start_feeds fk_rails_d91add3512; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.start_feeds
    ADD CONSTRAINT fk_rails_d91add3512 FOREIGN KEY (start_page_id) REFERENCES public.start_pages(id);


--
-- Name: blog_crawl_votes fk_rails_f74b6b39ca; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blog_crawl_votes
    ADD CONSTRAINT fk_rails_f74b6b39ca FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE;


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20201211221209'),
('20201211235524'),
('20201211235717'),
('20201221203545'),
('20201221203948'),
('20201222003840'),
('20201223002447'),
('20201223003011'),
('20201223003111'),
('20201223003402'),
('20201223003806'),
('20201223005223'),
('20201223190124'),
('20201223192043'),
('20201225012610'),
('20201225213107'),
('20201225224727'),
('20201226000744'),
('20201226002210'),
('20201226011605'),
('20201226012721'),
('20201226012915'),
('20210924002950'),
('20210924005119'),
('20210924021917'),
('20210924030232'),
('20211013194614'),
('20211013195012'),
('20211013195223'),
('20211013215140'),
('20211013220027'),
('20211013220113'),
('20211013224946'),
('20211013225920'),
('20211014202926'),
('20211014231606'),
('20211014232158'),
('20211014232819'),
('20211015001452'),
('20211018223825'),
('20211018224514'),
('20211018233856'),
('20211018234402'),
('20211018234839'),
('20211019223144'),
('20211022194206'),
('20211022194540'),
('20211025203926'),
('20211025210217'),
('20211207204405'),
('20211207205421'),
('20211208011458'),
('20211209232909'),
('20211222010540'),
('20211230004345'),
('20211230014420'),
('20220103221937'),
('20220105004242'),
('20220105210334'),
('20220105233450'),
('20220114233334'),
('20220115001649'),
('20220308005116'),
('20220321220933'),
('20220329191713'),
('20220331171951'),
('20220415183313'),
('20220415201523'),
('20220425183655'),
('20220428234040'),
('20220503200250'),
('20220503204702'),
('20220511235054'),
('20220512003521'),
('20220513002103'),
('20220513002912'),
('20220513010057'),
('20220513015140'),
('20220518233013'),
('20220519004059'),
('20220519014120'),
('20220521001101'),
('20220521002554'),
('20220602184712'),
('20220608213556'),
('20220608214452'),
('20220608215044'),
('20220608215349'),
('20220608215533'),
('20220613192525'),
('20220623000345'),
('20220623230024'),
('20220623233843'),
('20220624232743'),
('20220625000522'),
('20220625002918'),
('20220630213859');


