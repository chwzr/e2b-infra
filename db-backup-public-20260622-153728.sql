--
-- PostgreSQL database dump
--

-- Dumped from database version 15.8
-- Dumped by pg_dump version 15.12 (Homebrew)

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
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: backfill_env_id_from_assignment(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.backfill_env_id_from_assignment() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE env_builds SET env_id = NEW.env_id WHERE id = NEW.build_id AND env_id IS NULL;
    RETURN NEW;
END;
$$;


--
-- Name: backfill_team_id_from_assignment(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.backfill_team_id_from_assignment() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE env_builds
    SET team_id = (SELECT team_id FROM envs WHERE id = NEW.env_id)
    WHERE id = NEW.build_id AND team_id IS NULL;
    RETURN NEW;
END;
$$;


--
-- Name: compute_status_group(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compute_status_group() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.status_group := CASE
    WHEN NEW.status IN ('pending', 'waiting') THEN 'pending'
    WHEN NEW.status IN ('in_progress', 'building', 'snapshotting') THEN 'in_progress'
    WHEN NEW.status IN ('ready', 'uploaded', 'success') THEN 'ready'
    ELSE 'failed'
  END;
  RETURN NEW;
END;
$$;


--
-- Name: extra_for_post_user_signup(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.extra_for_post_user_signup(user_id uuid, team_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
BEGIN
END
$$;


--
-- Name: fix_snapshots_metadata_json_null(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fix_snapshots_metadata_json_null() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.metadata IS NULL OR NEW.metadata = 'null'::jsonb THEN
    NEW.metadata := '{}'::jsonb;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: generate_access_token(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_access_token() RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    access_token_prefix TEXT := 'sk_e2b_';
    generated_token TEXT;
BEGIN
    -- Generate a random 20 byte string and encode it as hex, so it's 40 characters
    generated_token := encode(extensions.gen_random_bytes(20), 'hex');
    RETURN access_token_prefix || generated_token;
END
$$;


--
-- Name: generate_default_team(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_default_team() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    team_id                 uuid;
BEGIN
    INSERT INTO public.teams(name, is_default, tier, email) VALUES (NEW.email, true, 'base', NEW.email) RETURNING id INTO team_id;
    INSERT INTO public.users_teams(user_id, team_id) VALUES (NEW.id, team_id);
    RAISE NOTICE 'Created default team for user % and team %', NEW.id, team_id;
    RETURN NEW;
END
$$;


--
-- Name: generate_team_api_key(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_team_api_key() RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    team_api_key_prefix TEXT := 'e2b_';
    generated_key TEXT;
BEGIN
    -- Generate a random 20 byte string and encode it as hex, so it's 40 characters
    generated_key := encode(extensions.gen_random_bytes(20), 'hex');
    RETURN team_api_key_prefix || generated_key;
END
$$;


--
-- Name: generate_team_slug(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_team_slug(name text) RETURNS text
    LANGUAGE plpgsql
    AS $$
    DECLARE
      base_name TEXT;
    BEGIN
      base_name := SPLIT_PART(name, '@', 1);

      RETURN LOWER(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            UNACCENT(TRIM(base_name)),
            '[^a-zA-Z0-9\s-]',
            '',
            'g'
          ),
          '\s+',
          '-',
          'g'
        )
      );
    END;
    $$;


--
-- Name: generate_team_slug_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_team_slug_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
      base_slug TEXT;
      test_slug TEXT;
      suffix TEXT;
    BEGIN
      IF NEW.slug IS NULL THEN
        base_slug := generate_team_slug(NEW.name);
        test_slug := base_slug;

        WHILE EXISTS (SELECT 1 FROM teams WHERE slug = test_slug) LOOP
          suffix := SUBSTRING(gen_random_uuid()::text, 1, 4);
          test_slug := base_slug || '-' || suffix;
        END LOOP;

        NEW.slug := test_slug;
      END IF;
      RETURN NEW;
    END;
    $$;


--
-- Name: is_member_of_team(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_member_of_team(_user_id uuid, _team_id uuid) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    AS $$
SELECT EXISTS (
    SELECT 1
    FROM public.users_teams ut
    WHERE ut.user_id = _user_id
      AND ut.team_id = _team_id
);
$$;


--
-- Name: post_user_signup(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.post_user_signup() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    team_id                 uuid;
BEGIN
    RAISE NOTICE 'Creating default team for user %', NEW.id;
    INSERT INTO public.teams(name, tier, email) VALUES (NEW.email, 'base_v1', NEW.email) RETURNING id INTO team_id;
    INSERT INTO public.users_teams(user_id, team_id, is_default) VALUES (NEW.id, team_id, true);
    RAISE NOTICE 'Created default team for user % and team %', NEW.id, team_id;

    PERFORM public.extra_for_post_user_signup(NEW.id, team_id);

    RETURN NEW;
END
$$;


--
-- Name: sync_delete_auth_users_to_public_users_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_delete_auth_users_to_public_users_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
    DELETE FROM public.users WHERE id = OLD.id;
    RETURN OLD;
END;
$$;


--
-- Name: sync_env_source_on_snapshot_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_env_source_on_snapshot_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE "public"."envs" SET source = 'snapshot' WHERE id = NEW.env_id;
    RETURN NEW;
END;
$$;


--
-- Name: sync_insert_auth_users_to_public_users_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_insert_auth_users_to_public_users_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
    INSERT INTO public.users (id, email)
    VALUES (NEW.id, NEW.email);

    RETURN NEW;
END;
$$;


--
-- Name: sync_update_auth_users_to_public_users_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_update_auth_users_to_public_users_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
    UPDATE public.users
    SET email = NEW.email,
        updated_at = now()
    WHERE id = NEW.id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User with id % does not exist in public.users', NEW.id;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: try_cast_uuid(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.try_cast_uuid(p_value text) RETURNS uuid
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    RETURN p_value::uuid;
EXCEPTION WHEN invalid_text_representation THEN
    RETURN NULL;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: _migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public._migrations (
    id integer NOT NULL,
    version_id bigint NOT NULL,
    is_applied boolean NOT NULL,
    tstamp timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: _migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public._migrations ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public._migrations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: access_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.access_tokens (
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    access_token_hash text NOT NULL,
    name text DEFAULT 'Unnamed Access Token'::text NOT NULL,
    access_token_prefix character varying(10) NOT NULL,
    access_token_length integer NOT NULL,
    access_token_mask_prefix character varying(5) NOT NULL,
    access_token_mask_suffix character varying(5) NOT NULL
);


--
-- Name: COLUMN access_tokens.access_token_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.access_tokens.access_token_hash IS 'sensitive';


--
-- Name: active_template_builds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_template_builds (
    build_id uuid NOT NULL,
    team_id uuid NOT NULL,
    template_id text NOT NULL,
    tags text[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: addons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.addons (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    team_id uuid NOT NULL,
    name text NOT NULL,
    description text,
    extra_concurrent_sandboxes bigint DEFAULT 0 NOT NULL,
    extra_concurrent_template_builds bigint DEFAULT 0 NOT NULL,
    extra_max_vcpu bigint DEFAULT 0 NOT NULL,
    extra_max_ram_mb bigint DEFAULT 0 NOT NULL,
    extra_disk_mb bigint DEFAULT 0 NOT NULL,
    valid_from timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    valid_to timestamp with time zone,
    added_by uuid NOT NULL,
    idempotency_key text,
    CONSTRAINT addons_valid_dates_check CHECK (((valid_to IS NULL) OR (valid_to > valid_from)))
);


--
-- Name: clusters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clusters (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    endpoint text NOT NULL,
    endpoint_tls boolean DEFAULT true NOT NULL,
    token text NOT NULL,
    sandbox_proxy_domain text
);


--
-- Name: env_aliases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.env_aliases (
    alias text NOT NULL,
    is_renamable boolean DEFAULT true NOT NULL,
    env_id text NOT NULL,
    namespace text,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: env_build_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.env_build_assignments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    env_id text NOT NULL,
    build_id uuid NOT NULL,
    tag text NOT NULL,
    source text DEFAULT 'app'::text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: env_builds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.env_builds (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    finished_at timestamp with time zone,
    status text DEFAULT 'waiting'::text NOT NULL,
    dockerfile text,
    start_cmd text,
    vcpu bigint NOT NULL,
    ram_mb bigint NOT NULL,
    free_disk_size_mb bigint NOT NULL,
    total_disk_size_mb bigint,
    kernel_version text DEFAULT 'vmlinux-5.10.186'::text NOT NULL,
    firecracker_version text NOT NULL,
    env_id text,
    envd_version text,
    ready_cmd text,
    cluster_node_id text,
    reason jsonb DEFAULT '{}'::jsonb NOT NULL,
    version text,
    cpu_architecture text,
    cpu_family text,
    cpu_model text,
    cpu_model_name text,
    cpu_flags text[],
    status_group text NOT NULL,
    team_id uuid
);


--
-- Name: envs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.envs (
    id text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    public boolean DEFAULT false NOT NULL,
    build_count integer DEFAULT 1 NOT NULL,
    spawn_count bigint DEFAULT '0'::bigint NOT NULL,
    last_spawned_at timestamp with time zone,
    team_id uuid NOT NULL,
    created_by uuid,
    cluster_id uuid,
    source text DEFAULT 'template'::text NOT NULL
);


--
-- Name: COLUMN envs.spawn_count; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.envs.spawn_count IS 'Number of times the env was spawned';


--
-- Name: COLUMN envs.last_spawned_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.envs.last_spawned_at IS 'Timestamp of the last time the env was spawned';


--
-- Name: snapshot_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.snapshot_templates (
    env_id text NOT NULL,
    sandbox_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    origin_node_id text,
    build_id uuid
);


--
-- Name: snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.snapshots (
    created_at timestamp with time zone DEFAULT now(),
    env_id text NOT NULL,
    sandbox_id text NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    base_env_id text NOT NULL,
    sandbox_started_at timestamp with time zone NOT NULL,
    env_secure boolean DEFAULT false NOT NULL,
    origin_node_id text NOT NULL,
    allow_internet_access boolean,
    auto_pause boolean DEFAULT false NOT NULL,
    team_id uuid NOT NULL,
    config jsonb
);


--
-- Name: sutekh; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sutekh (
    id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: sutekh_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.sutekh ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.sutekh_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: team_api_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team_api_keys (
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    team_id uuid NOT NULL,
    updated_at timestamp with time zone,
    name text DEFAULT 'Unnamed API Key'::text NOT NULL,
    last_used timestamp with time zone,
    created_by uuid,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    api_key_hash text NOT NULL,
    api_key_prefix character varying(10) NOT NULL,
    api_key_length integer NOT NULL,
    api_key_mask_prefix character varying(5) NOT NULL,
    api_key_mask_suffix character varying(5) NOT NULL
);


--
-- Name: COLUMN team_api_keys.api_key_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.team_api_keys.api_key_hash IS 'sensitive';


--
-- Name: teams; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teams (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    is_blocked boolean DEFAULT false NOT NULL,
    name text NOT NULL,
    tier text NOT NULL,
    email character varying(255) NOT NULL,
    is_banned boolean DEFAULT false NOT NULL,
    blocked_reason text,
    cluster_id uuid,
    slug text NOT NULL,
    sandbox_scheduling_labels text[] DEFAULT '{}'::text[] NOT NULL
);


--
-- Name: tiers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tiers (
    id text NOT NULL,
    name text NOT NULL,
    disk_mb bigint DEFAULT '512'::bigint NOT NULL,
    concurrent_instances bigint NOT NULL,
    max_length_hours bigint NOT NULL,
    max_vcpu bigint DEFAULT '8'::bigint NOT NULL,
    max_ram_mb bigint DEFAULT '8192'::bigint NOT NULL,
    concurrent_template_builds bigint DEFAULT 20 NOT NULL,
    CONSTRAINT tiers_concurrent_sessions_check CHECK ((concurrent_instances > 0)),
    CONSTRAINT tiers_concurrent_template_builds_check CHECK ((concurrent_template_builds > 0)),
    CONSTRAINT tiers_disk_mb_check CHECK ((disk_mb > 0))
);


--
-- Name: COLUMN tiers.concurrent_instances; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tiers.concurrent_instances IS 'The number of instances the team can run concurrently';


--
-- Name: COLUMN tiers.concurrent_template_builds; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tiers.concurrent_template_builds IS 'The number of concurrent template builds the team can run';


--
-- Name: team_limits; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.team_limits WITH (security_invoker='on') AS
 SELECT t.id,
    tier.max_length_hours,
    (tier.concurrent_instances + a.extra_concurrent_sandboxes) AS concurrent_sandboxes,
    (tier.concurrent_template_builds + a.extra_concurrent_template_builds) AS concurrent_template_builds,
    (tier.max_vcpu + a.extra_max_vcpu) AS max_vcpu,
    (tier.max_ram_mb + a.extra_max_ram_mb) AS max_ram_mb,
    (tier.disk_mb + a.extra_disk_mb) AS disk_mb
   FROM ((public.teams t
     JOIN public.tiers tier ON ((t.tier = tier.id)))
     LEFT JOIN LATERAL ( SELECT (COALESCE(sum(addon.extra_concurrent_sandboxes), (0)::numeric))::bigint AS extra_concurrent_sandboxes,
            (COALESCE(sum(addon.extra_concurrent_template_builds), (0)::numeric))::bigint AS extra_concurrent_template_builds,
            (COALESCE(sum(addon.extra_max_vcpu), (0)::numeric))::bigint AS extra_max_vcpu,
            (COALESCE(sum(addon.extra_max_ram_mb), (0)::numeric))::bigint AS extra_max_ram_mb,
            (COALESCE(sum(addon.extra_disk_mb), (0)::numeric))::bigint AS extra_disk_mb
           FROM public.addons addon
          WHERE ((addon.team_id = t.id) AND (addon.valid_from <= now()) AND ((addon.valid_to IS NULL) OR (addon.valid_to > now())))) a ON (true));


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    id uuid NOT NULL,
    email text NOT NULL
);


--
-- Name: users_teams; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users_teams (
    id bigint NOT NULL,
    user_id uuid NOT NULL,
    team_id uuid NOT NULL,
    is_default boolean DEFAULT false NOT NULL,
    added_by uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    uuid_id uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: users_teams_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.users_teams ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.users_teams_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: volumes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.volumes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    team_id uuid NOT NULL,
    name character varying(250) NOT NULL,
    volume_type character varying(250) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Data for Name: _migrations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public._migrations (id, version_id, is_applied, tstamp) FROM stdin;
1	0	t	2026-04-24 22:53:49.231762
2	20000101000000	t	2026-04-24 22:53:49.247486
3	20000101000001	t	2026-04-24 22:53:49.255287
4	20231124185944	t	2026-04-24 22:53:49.257645
5	20231220094836	t	2026-04-24 22:53:49.288388
6	20231222181015	t	2026-04-24 22:53:49.296761
7	20240103104619	t	2026-04-24 22:53:49.299567
8	20240106121919	t	2026-04-24 22:53:49.303554
9	20240202120312	t	2026-04-24 22:53:49.30694
10	20240219190940	t	2026-04-24 22:53:49.310709
11	20240221023613	t	2026-04-24 22:53:49.315836
12	20240221215408	t	2026-04-24 22:53:49.317481
13	20240305221944	t	2026-04-24 22:53:49.320788
14	20240315165236	t	2026-04-24 22:53:49.324669
15	20240605070918	t	2026-04-24 22:53:49.335976
16	20240625095352	t	2026-04-24 22:53:49.348898
17	20240728094137	t	2026-04-24 22:53:49.351868
18	20240909142106	t	2026-04-24 22:53:49.357117
19	20241120222814	t	2026-04-24 22:53:49.36048
20	20241121225404	t	2026-04-24 22:53:49.369364
21	20241127174604	t	2026-04-24 22:53:49.377813
22	20241206124325	t	2026-04-24 22:53:49.382371
23	20241213142106	t	2026-04-24 22:53:49.388397
24	20250106142106	t	2026-04-24 22:53:49.389851
25	20250206105106	t	2026-04-24 22:53:49.395397
26	20250211160814	t	2026-04-24 22:53:49.397202
27	20250306105106	t	2026-04-24 22:53:49.407683
28	20250404151700	t	2026-04-24 22:53:49.429127
29	20250409113306	t	2026-04-24 22:53:49.432342
30	20250506112836	t	2026-04-24 22:53:49.436411
31	20250507134356	t	2026-04-24 22:53:49.438707
32	20250513111201	t	2026-04-24 22:53:49.440518
33	20250522105042	t	2026-04-24 22:53:49.443774
34	20250528203546	t	2026-04-24 22:53:49.446897
35	20250606204750	t	2026-04-24 22:53:49.449624
36	20250606213446	t	2026-04-24 22:53:49.453553
37	20250624001047	t	2026-04-24 22:53:49.463286
38	20250624001048	t	2026-04-24 22:53:49.466162
39	20250624001049	t	2026-04-24 22:53:49.471748
40	20250624232413	t	2026-04-24 22:53:49.475491
41	20250708135400	t	2026-04-24 22:53:49.483721
42	20250708135401	t	2026-04-24 22:53:49.484738
43	20250714132924	t	2026-04-24 22:53:49.487486
44	20250728085406	t	2026-04-24 22:53:49.490854
45	20250802144312	t	2026-04-24 22:53:49.493786
46	20250815181502	t	2026-04-24 22:53:49.497395
47	20250818114512	t	2026-04-24 22:53:49.515142
48	20250820102103	t	2026-04-24 22:53:49.630781
49	20250824185633	t	2026-04-24 22:53:49.631964
50	20250824185634	t	2026-04-24 22:53:49.635168
51	20250825100000	t	2026-04-24 22:53:49.63844
52	20250825102440	t	2026-04-24 22:53:49.651362
53	20250825102800	t	2026-04-24 22:53:49.652609
54	20250825102900	t	2026-04-24 22:53:49.662502
55	20250901161352	t	2026-04-24 22:53:49.666636
56	20250905134524	t	2026-04-24 22:53:49.670541
57	20250910063940	t	2026-04-24 22:53:49.674051
58	20250910072612	t	2026-04-24 22:53:49.680436
59	20250910124212	t	2026-04-24 22:53:49.683853
60	20250923094021	t	2026-04-24 22:53:49.688612
61	20250923103546	t	2026-04-24 22:53:49.701096
62	20250923103614	t	2026-04-24 22:53:49.702171
63	20251009170758	t	2026-04-24 22:53:49.705302
64	20251011200438	t	2026-04-24 22:53:49.710499
65	20251018100653	t	2026-04-24 22:53:49.734139
66	20251026192416	t	2026-04-24 22:53:49.737804
67	20251030130958	t	2026-04-24 22:53:49.748722
68	20251106172810	t	2026-04-24 22:53:49.749963
69	20251121101953	t	2026-04-24 22:53:49.753128
70	20251127000000	t	2026-04-24 22:53:49.756362
71	20251216135834	t	2026-04-24 22:53:49.888803
72	20251217000000	t	2026-04-24 22:53:49.889991
73	20251218160000	t	2026-04-24 22:53:49.945584
74	20251218170000	t	2026-04-24 22:53:49.954988
75	20260121175429	t	2026-04-24 22:53:49.956183
76	20260121175430	t	2026-04-24 22:53:50.006738
77	20260127120000	t	2026-04-24 22:53:50.031848
78	20260129105527	t	2026-04-24 22:53:50.03315
79	20260204172712	t	2026-04-24 22:53:50.045834
80	20260210120000	t	2026-04-24 22:53:50.152709
81	20260210120001	t	2026-04-24 22:53:50.161967
82	20260210120002	t	2026-04-24 22:53:50.180552
83	20260211120000	t	2026-04-24 22:53:50.190737
84	20260216120000	t	2026-04-24 22:53:50.197443
85	20260218120000	t	2026-04-24 22:53:50.217927
86	20260225120000	t	2026-04-24 22:53:50.224604
87	20260228120000	t	2026-04-24 22:53:50.225912
88	20260304120000	t	2026-04-24 22:53:50.229248
89	20260305120000	t	2026-04-24 22:53:50.247785
90	20260305130000	t	2026-04-24 22:53:50.24931
91	20260309120000	t	2026-04-24 22:53:50.263186
92	20260310120000	t	2026-04-24 22:53:50.4035
93	20260312120000	t	2026-04-24 22:53:50.415448
94	20260313120000	t	2026-04-24 22:53:50.422947
95	20260314120000	t	2026-04-24 22:53:50.42438
96	20260316120000	t	2026-04-24 22:53:50.446716
97	20260316130000	t	2026-04-24 22:53:50.487816
\.


--
-- Data for Name: access_tokens; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.access_tokens (user_id, created_at, id, access_token_hash, name, access_token_prefix, access_token_length, access_token_mask_prefix, access_token_mask_suffix) FROM stdin;
9c5250da-12b9-4d22-bab8-ccc4c625f35e	2026-04-25 06:10:01.554201+00	437b0656-233d-4547-9246-e1e399c165c7	$sha256$HBYHdAnhdZIBIDs/w/B7se6KSmwnnAJbqMzDG4ameTY	Seed Access Token	sk_e2b_	40	81	71cf
\.


--
-- Data for Name: active_template_builds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.active_template_builds (build_id, team_id, template_id, tags, created_at) FROM stdin;
55e1be2a-0754-4971-9dfe-f7362025ee19	ff47822c-6a46-4f2b-adf5-66a402980f62	0y5wsbhhevg9ajcsthpb	{default}	2026-04-25 22:30:14.612431+00
\.


--
-- Data for Name: addons; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.addons (id, team_id, name, description, extra_concurrent_sandboxes, extra_concurrent_template_builds, extra_max_vcpu, extra_max_ram_mb, extra_disk_mb, valid_from, valid_to, added_by, idempotency_key) FROM stdin;
\.


--
-- Data for Name: clusters; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.clusters (id, endpoint, endpoint_tls, token, sandbox_proxy_domain) FROM stdin;
\.


--
-- Data for Name: env_aliases; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.env_aliases (alias, is_renamable, env_id, namespace, id) FROM stdin;
base	t	upoql7xdcpxelhvkztd8	e2b	a1b9d78a-4b6b-4ac6-b004-e6501ef2ccc0
nextjs-app	t	0y5wsbhhevg9ajcsthpb	e2b	4866568e-f4c7-4e5e-b579-e86639a05f88
\.


--
-- Data for Name: env_build_assignments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.env_build_assignments (id, env_id, build_id, tag, source, created_at) FROM stdin;
3b94227a-d49a-4799-8cee-ae82fdbdb8a1	upoql7xdcpxelhvkztd8	3d770b56-2385-4eaf-91ba-38b367af5741	default	app	2026-04-25 06:13:35.126526+00
4223b9dc-cd87-4b28-a405-51f44953352c	upoql7xdcpxelhvkztd8	a7c3d45f-d97b-4ead-a189-3dbbf9038532	default	app	2026-04-25 06:23:12.542267+00
6faaef7a-c320-4973-af7f-a4b72e82166d	upoql7xdcpxelhvkztd8	4da5b425-b122-4c0d-a4fa-2345b894846d	default	app	2026-04-25 06:25:28.056517+00
6589f184-c00b-4af3-a2da-66152e3292b3	upoql7xdcpxelhvkztd8	a1848708-b682-4097-b07a-4a005ac6572a	default	app	2026-04-25 06:26:09.358177+00
154dae66-9d50-493e-8506-b980bcfd3dc2	upoql7xdcpxelhvkztd8	ad04d8e1-4f94-4cd7-96b5-2e386c2ed78e	default	app	2026-04-25 06:29:20.537332+00
39da2ee3-7aba-4839-8e4b-25bf4b54c55a	upoql7xdcpxelhvkztd8	dd956f75-841e-47cb-92c9-5dbeadaa9e3f	default	app	2026-04-25 06:30:51.537499+00
038a7b78-fb30-47c0-8cb6-4f48db7f1115	upoql7xdcpxelhvkztd8	40905ca6-a8b1-465e-8159-a4a806238b60	default	app	2026-04-25 06:33:14.220077+00
edb8190d-5340-4fa7-8b90-b5a30ee8322a	upoql7xdcpxelhvkztd8	a3621ec5-c87f-4deb-814d-2283f583b9b0	default	app	2026-04-25 06:33:21.722181+00
a5bc7da7-6a5c-453e-839d-bef0c8fbbd66	upoql7xdcpxelhvkztd8	4bb49522-ce2c-406c-b6ad-9899047982c0	default	app	2026-04-25 06:33:47.771322+00
d1c820dc-2892-4d2f-b6d4-902ee4a1a772	0y5wsbhhevg9ajcsthpb	55e1be2a-0754-4971-9dfe-f7362025ee19	default	app	2026-04-25 22:30:14.612431+00
\.


--
-- Data for Name: env_builds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.env_builds (id, created_at, updated_at, finished_at, status, dockerfile, start_cmd, vcpu, ram_mb, free_disk_size_mb, total_disk_size_mb, kernel_version, firecracker_version, env_id, envd_version, ready_cmd, cluster_node_id, reason, version, cpu_architecture, cpu_family, cpu_model, cpu_model_name, cpu_flags, status_group, team_id) FROM stdin;
3d770b56-2385-4eaf-91ba-38b367af5741	2026-04-25 06:13:35.126526+00	2026-04-25 06:13:35.126526+00	2026-04-25 06:13:40.203324+00	failed	{"from_image":"e2bdev/base","from_template":null,"steps":[]}	\N	2	512	512	\N	vmlinux-6.1.158	v1.12.1_210cbac	upoql7xdcpxelhvkztd8	\N	\N	e2b-build-0	{"message": "build timed out"}	\N	amd64	25	97	AMD Ryzen 7 7700 8-Core Processor	{fpu,vme,de,pse,tsc,msr,pae,mce,cx8,apic,sep,mtrr,pge,mca,cmov,pat,pse36,clflush,mmx,fxsr,sse,sse2,ht,syscall,nx,mmxext,fxsr_opt,pdpe1gb,rdtscp,lm,rep_good,nopl,cpuid,extd_apicid,tsc_known_freq,pni,pclmulqdq,ssse3,fma,cx16,sse4_1,sse4_2,x2apic,movbe,popcnt,tsc_deadline_timer,aes,xsave,avx,f16c,rdrand,hypervisor,lahf_lm,cmp_legacy,svm,cr8_legacy,abm,sse4a,misalignsse,3dnowprefetch,osvw,perfctr_core,ssbd,perfmon_v2,ibrs,ibpb,stibp,ibrs_enhanced,vmmcall,fsgsbase,tsc_adjust,bmi1,avx2,smep,bmi2,erms,invpcid,avx512f,avx512dq,rdseed,adx,smap,avx512ifma,clflushopt,clwb,avx512cd,sha_ni,avx512bw,avx512vl,xsaveopt,xsavec,xgetbv1,xsaves,avx512_bf16,clzero,xsaveerptr,wbnoinvd,arat,npt,lbrv,nrip_save,tsc_scale,vmcb_clean,flushbyasid,pausefilter,pfthreshold,vgif,vnmi,avx512vbmi,umip,pku,ospke,avx512_vbmi2,gfni,vaes,vpclmulqdq,avx512_vnni,avx512_bitalg,avx512_vpopcntdq,rdpid,overflow_recov,succor,fsrm,flush_l1d}	failed	ff47822c-6a46-4f2b-adf5-66a402980f62
a1848708-b682-4097-b07a-4a005ac6572a	2026-04-25 06:26:09.358177+00	2026-04-25 06:26:09.358177+00	2026-04-25 06:26:44.430183+00	failed	{"from_image":"e2bdev/base","from_template":null,"steps":[]}	\N	2	512	512	\N	vmlinux-6.1.158	v1.12.1_210cbac	upoql7xdcpxelhvkztd8	\N	\N	e2b-build-0	{"message": "build timed out"}	\N	amd64	25	97	AMD Ryzen 7 7700 8-Core Processor	{fpu,vme,de,pse,tsc,msr,pae,mce,cx8,apic,sep,mtrr,pge,mca,cmov,pat,pse36,clflush,mmx,fxsr,sse,sse2,ht,syscall,nx,mmxext,fxsr_opt,pdpe1gb,rdtscp,lm,rep_good,nopl,cpuid,extd_apicid,tsc_known_freq,pni,pclmulqdq,ssse3,fma,cx16,sse4_1,sse4_2,x2apic,movbe,popcnt,tsc_deadline_timer,aes,xsave,avx,f16c,rdrand,hypervisor,lahf_lm,cmp_legacy,svm,cr8_legacy,abm,sse4a,misalignsse,3dnowprefetch,osvw,perfctr_core,ssbd,perfmon_v2,ibrs,ibpb,stibp,ibrs_enhanced,vmmcall,fsgsbase,tsc_adjust,bmi1,avx2,smep,bmi2,erms,invpcid,avx512f,avx512dq,rdseed,adx,smap,avx512ifma,clflushopt,clwb,avx512cd,sha_ni,avx512bw,avx512vl,xsaveopt,xsavec,xgetbv1,xsaves,avx512_bf16,clzero,xsaveerptr,wbnoinvd,arat,npt,lbrv,nrip_save,tsc_scale,vmcb_clean,flushbyasid,pausefilter,pfthreshold,vgif,vnmi,avx512vbmi,umip,pku,ospke,avx512_vbmi2,gfni,vaes,vpclmulqdq,avx512_vnni,avx512_bitalg,avx512_vpopcntdq,rdpid,overflow_recov,succor,fsrm,flush_l1d}	failed	ff47822c-6a46-4f2b-adf5-66a402980f62
dd956f75-841e-47cb-92c9-5dbeadaa9e3f	2026-04-25 06:30:51.537499+00	2026-04-25 06:30:51.537499+00	2026-04-25 06:31:21.606597+00	failed	{"from_image":"e2bdev/base","from_template":null,"steps":[]}	\N	2	512	512	\N	vmlinux-6.1.158	v1.12.1_210cbac	upoql7xdcpxelhvkztd8	\N	\N	e2b-build-0	{"message": "build timed out"}	\N	amd64	25	97	AMD Ryzen 7 7700 8-Core Processor	{fpu,vme,de,pse,tsc,msr,pae,mce,cx8,apic,sep,mtrr,pge,mca,cmov,pat,pse36,clflush,mmx,fxsr,sse,sse2,ht,syscall,nx,mmxext,fxsr_opt,pdpe1gb,rdtscp,lm,rep_good,nopl,cpuid,extd_apicid,tsc_known_freq,pni,pclmulqdq,ssse3,fma,cx16,sse4_1,sse4_2,x2apic,movbe,popcnt,tsc_deadline_timer,aes,xsave,avx,f16c,rdrand,hypervisor,lahf_lm,cmp_legacy,svm,cr8_legacy,abm,sse4a,misalignsse,3dnowprefetch,osvw,perfctr_core,ssbd,perfmon_v2,ibrs,ibpb,stibp,ibrs_enhanced,vmmcall,fsgsbase,tsc_adjust,bmi1,avx2,smep,bmi2,erms,invpcid,avx512f,avx512dq,rdseed,adx,smap,avx512ifma,clflushopt,clwb,avx512cd,sha_ni,avx512bw,avx512vl,xsaveopt,xsavec,xgetbv1,xsaves,avx512_bf16,clzero,xsaveerptr,wbnoinvd,arat,npt,lbrv,nrip_save,tsc_scale,vmcb_clean,flushbyasid,pausefilter,pfthreshold,vgif,vnmi,avx512vbmi,umip,pku,ospke,avx512_vbmi2,gfni,vaes,vpclmulqdq,avx512_vnni,avx512_bitalg,avx512_vpopcntdq,rdpid,overflow_recov,succor,fsrm,flush_l1d}	failed	ff47822c-6a46-4f2b-adf5-66a402980f62
a7c3d45f-d97b-4ead-a189-3dbbf9038532	2026-04-25 06:23:12.542267+00	2026-04-25 06:23:12.542267+00	2026-04-25 06:23:17.616905+00	failed	{"from_image":"e2bdev/base","from_template":null,"steps":[]}	\N	2	512	512	\N	vmlinux-6.1.158	v1.12.1_210cbac	upoql7xdcpxelhvkztd8	\N	\N	e2b-build-0	{"message": "build timed out"}	\N	amd64	25	97	AMD Ryzen 7 7700 8-Core Processor	{fpu,vme,de,pse,tsc,msr,pae,mce,cx8,apic,sep,mtrr,pge,mca,cmov,pat,pse36,clflush,mmx,fxsr,sse,sse2,ht,syscall,nx,mmxext,fxsr_opt,pdpe1gb,rdtscp,lm,rep_good,nopl,cpuid,extd_apicid,tsc_known_freq,pni,pclmulqdq,ssse3,fma,cx16,sse4_1,sse4_2,x2apic,movbe,popcnt,tsc_deadline_timer,aes,xsave,avx,f16c,rdrand,hypervisor,lahf_lm,cmp_legacy,svm,cr8_legacy,abm,sse4a,misalignsse,3dnowprefetch,osvw,perfctr_core,ssbd,perfmon_v2,ibrs,ibpb,stibp,ibrs_enhanced,vmmcall,fsgsbase,tsc_adjust,bmi1,avx2,smep,bmi2,erms,invpcid,avx512f,avx512dq,rdseed,adx,smap,avx512ifma,clflushopt,clwb,avx512cd,sha_ni,avx512bw,avx512vl,xsaveopt,xsavec,xgetbv1,xsaves,avx512_bf16,clzero,xsaveerptr,wbnoinvd,arat,npt,lbrv,nrip_save,tsc_scale,vmcb_clean,flushbyasid,pausefilter,pfthreshold,vgif,vnmi,avx512vbmi,umip,pku,ospke,avx512_vbmi2,gfni,vaes,vpclmulqdq,avx512_vnni,avx512_bitalg,avx512_vpopcntdq,rdpid,overflow_recov,succor,fsrm,flush_l1d}	failed	ff47822c-6a46-4f2b-adf5-66a402980f62
4da5b425-b122-4c0d-a4fa-2345b894846d	2026-04-25 06:25:28.056517+00	2026-04-25 06:25:28.056517+00	2026-04-25 06:25:45.12199+00	failed	{"from_image":"e2bdev/base","from_template":null,"steps":[]}	\N	2	512	512	\N	vmlinux-6.1.158	v1.12.1_210cbac	upoql7xdcpxelhvkztd8	\N	\N	e2b-build-0	{"message": "build was cancelled"}	\N	amd64	25	97	AMD Ryzen 7 7700 8-Core Processor	{fpu,vme,de,pse,tsc,msr,pae,mce,cx8,apic,sep,mtrr,pge,mca,cmov,pat,pse36,clflush,mmx,fxsr,sse,sse2,ht,syscall,nx,mmxext,fxsr_opt,pdpe1gb,rdtscp,lm,rep_good,nopl,cpuid,extd_apicid,tsc_known_freq,pni,pclmulqdq,ssse3,fma,cx16,sse4_1,sse4_2,x2apic,movbe,popcnt,tsc_deadline_timer,aes,xsave,avx,f16c,rdrand,hypervisor,lahf_lm,cmp_legacy,svm,cr8_legacy,abm,sse4a,misalignsse,3dnowprefetch,osvw,perfctr_core,ssbd,perfmon_v2,ibrs,ibpb,stibp,ibrs_enhanced,vmmcall,fsgsbase,tsc_adjust,bmi1,avx2,smep,bmi2,erms,invpcid,avx512f,avx512dq,rdseed,adx,smap,avx512ifma,clflushopt,clwb,avx512cd,sha_ni,avx512bw,avx512vl,xsaveopt,xsavec,xgetbv1,xsaves,avx512_bf16,clzero,xsaveerptr,wbnoinvd,arat,npt,lbrv,nrip_save,tsc_scale,vmcb_clean,flushbyasid,pausefilter,pfthreshold,vgif,vnmi,avx512vbmi,umip,pku,ospke,avx512_vbmi2,gfni,vaes,vpclmulqdq,avx512_vnni,avx512_bitalg,avx512_vpopcntdq,rdpid,overflow_recov,succor,fsrm,flush_l1d}	failed	ff47822c-6a46-4f2b-adf5-66a402980f62
ad04d8e1-4f94-4cd7-96b5-2e386c2ed78e	2026-04-25 06:29:20.537332+00	2026-04-25 06:29:20.537332+00	2026-04-25 06:29:54.605188+00	failed	{"from_image":"e2bdev/base","from_template":null,"steps":[]}	\N	2	512	512	\N	vmlinux-6.1.158	v1.12.1_210cbac	upoql7xdcpxelhvkztd8	\N	\N	e2b-build-0	{"message": "build timed out"}	\N	amd64	25	97	AMD Ryzen 7 7700 8-Core Processor	{fpu,vme,de,pse,tsc,msr,pae,mce,cx8,apic,sep,mtrr,pge,mca,cmov,pat,pse36,clflush,mmx,fxsr,sse,sse2,ht,syscall,nx,mmxext,fxsr_opt,pdpe1gb,rdtscp,lm,rep_good,nopl,cpuid,extd_apicid,tsc_known_freq,pni,pclmulqdq,ssse3,fma,cx16,sse4_1,sse4_2,x2apic,movbe,popcnt,tsc_deadline_timer,aes,xsave,avx,f16c,rdrand,hypervisor,lahf_lm,cmp_legacy,svm,cr8_legacy,abm,sse4a,misalignsse,3dnowprefetch,osvw,perfctr_core,ssbd,perfmon_v2,ibrs,ibpb,stibp,ibrs_enhanced,vmmcall,fsgsbase,tsc_adjust,bmi1,avx2,smep,bmi2,erms,invpcid,avx512f,avx512dq,rdseed,adx,smap,avx512ifma,clflushopt,clwb,avx512cd,sha_ni,avx512bw,avx512vl,xsaveopt,xsavec,xgetbv1,xsaves,avx512_bf16,clzero,xsaveerptr,wbnoinvd,arat,npt,lbrv,nrip_save,tsc_scale,vmcb_clean,flushbyasid,pausefilter,pfthreshold,vgif,vnmi,avx512vbmi,umip,pku,ospke,avx512_vbmi2,gfni,vaes,vpclmulqdq,avx512_vnni,avx512_bitalg,avx512_vpopcntdq,rdpid,overflow_recov,succor,fsrm,flush_l1d}	failed	ff47822c-6a46-4f2b-adf5-66a402980f62
40905ca6-a8b1-465e-8159-a4a806238b60	2026-04-25 06:33:14.220077+00	2026-04-25 06:33:21.722181+00	2026-04-25 06:33:21.722181+00	failed		\N	2	512	512	\N	vmlinux-6.1.158	v1.12.1_210cbac	upoql7xdcpxelhvkztd8	\N	\N	\N	{"message": "The build was canceled because it was superseded by a newer one."}	v2.1.0	\N	\N	\N	\N	\N	failed	ff47822c-6a46-4f2b-adf5-66a402980f62
a3621ec5-c87f-4deb-814d-2283f583b9b0	2026-04-25 06:33:21.722181+00	2026-04-25 06:33:47.771322+00	2026-04-25 06:33:47.771322+00	failed		\N	2	512	512	\N	vmlinux-6.1.158	v1.12.1_210cbac	upoql7xdcpxelhvkztd8	\N	\N	\N	{"message": "The build was canceled because it was superseded by a newer one."}	v2.1.0	\N	\N	\N	\N	\N	failed	ff47822c-6a46-4f2b-adf5-66a402980f62
4bb49522-ce2c-406c-b6ad-9899047982c0	2026-04-25 06:33:47.771322+00	2026-04-25 06:33:47.771322+00	2026-04-25 06:34:31.844082+00	uploaded	{"from_image":"e2bdev/base","from_template":null,"steps":[]}	\N	2	512	512	2743	vmlinux-6.1.158	v1.12.1_210cbac	upoql7xdcpxelhvkztd8	0.5.11	\N	e2b-build-0	{"message": ""}	\N	amd64	25	97	AMD Ryzen 7 7700 8-Core Processor	{fpu,vme,de,pse,tsc,msr,pae,mce,cx8,apic,sep,mtrr,pge,mca,cmov,pat,pse36,clflush,mmx,fxsr,sse,sse2,ht,syscall,nx,mmxext,fxsr_opt,pdpe1gb,rdtscp,lm,rep_good,nopl,cpuid,extd_apicid,tsc_known_freq,pni,pclmulqdq,ssse3,fma,cx16,sse4_1,sse4_2,x2apic,movbe,popcnt,tsc_deadline_timer,aes,xsave,avx,f16c,rdrand,hypervisor,lahf_lm,cmp_legacy,svm,cr8_legacy,abm,sse4a,misalignsse,3dnowprefetch,osvw,perfctr_core,ssbd,perfmon_v2,ibrs,ibpb,stibp,ibrs_enhanced,vmmcall,fsgsbase,tsc_adjust,bmi1,avx2,smep,bmi2,erms,invpcid,avx512f,avx512dq,rdseed,adx,smap,avx512ifma,clflushopt,clwb,avx512cd,sha_ni,avx512bw,avx512vl,xsaveopt,xsavec,xgetbv1,xsaves,avx512_bf16,clzero,xsaveerptr,wbnoinvd,arat,npt,lbrv,nrip_save,tsc_scale,vmcb_clean,flushbyasid,pausefilter,pfthreshold,vgif,vnmi,avx512vbmi,umip,pku,ospke,avx512_vbmi2,gfni,vaes,vpclmulqdq,avx512_vnni,avx512_bitalg,avx512_vpopcntdq,rdpid,overflow_recov,succor,fsrm,flush_l1d}	ready	ff47822c-6a46-4f2b-adf5-66a402980f62
55e1be2a-0754-4971-9dfe-f7362025ee19	2026-04-25 22:30:14.612431+00	2026-04-25 22:30:14.612431+00	2026-04-25 22:30:14.64927+00	building	{"from_image":"node:21-slim","from_template":null,"steps":[{"args":["/home/user/nextjs-app"],"force":false,"type":"WORKDIR"},{"args":["npx create-next-app@14.2.30 . --ts --tailwind --no-eslint --import-alias \\"@/*\\" --use-npm --no-app --no-src-dir"],"force":false,"type":"RUN"},{"args":["npx shadcn@2.1.7 init -d"],"force":false,"type":"RUN"},{"args":["npx shadcn@2.1.7 add --all"],"force":false,"type":"RUN"},{"args":["mv /home/user/nextjs-app/* /home/user/ \\u0026\\u0026 rm -rf /home/user/nextjs-app"],"force":false,"type":"RUN"},{"args":["/home/user"],"force":false,"type":"WORKDIR"}]}	npx next --turbo	4	4096	512	\N	vmlinux-6.1.158	v1.12.1_210cbac	0y5wsbhhevg9ajcsthpb	\N	curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 | grep -q "200"	e2b-build-0	{"message": ""}	\N	amd64	25	97	AMD Ryzen 7 7700 8-Core Processor	{fpu,vme,de,pse,tsc,msr,pae,mce,cx8,apic,sep,mtrr,pge,mca,cmov,pat,pse36,clflush,mmx,fxsr,sse,sse2,ht,syscall,nx,mmxext,fxsr_opt,pdpe1gb,rdtscp,lm,rep_good,nopl,cpuid,extd_apicid,tsc_known_freq,pni,pclmulqdq,ssse3,fma,cx16,sse4_1,sse4_2,x2apic,movbe,popcnt,tsc_deadline_timer,aes,xsave,avx,f16c,rdrand,hypervisor,lahf_lm,cmp_legacy,svm,cr8_legacy,abm,sse4a,misalignsse,3dnowprefetch,osvw,perfctr_core,ssbd,perfmon_v2,ibrs,ibpb,stibp,ibrs_enhanced,vmmcall,fsgsbase,tsc_adjust,bmi1,avx2,smep,bmi2,erms,invpcid,avx512f,avx512dq,rdseed,adx,smap,avx512ifma,clflushopt,clwb,avx512cd,sha_ni,avx512bw,avx512vl,xsaveopt,xsavec,xgetbv1,xsaves,avx512_bf16,clzero,xsaveerptr,wbnoinvd,arat,npt,lbrv,nrip_save,tsc_scale,vmcb_clean,flushbyasid,pausefilter,pfthreshold,vgif,vnmi,avx512vbmi,umip,pku,ospke,avx512_vbmi2,gfni,vaes,vpclmulqdq,avx512_vnni,avx512_bitalg,avx512_vpopcntdq,rdpid,overflow_recov,succor,fsrm,flush_l1d}	in_progress	ff47822c-6a46-4f2b-adf5-66a402980f62
\.


--
-- Data for Name: envs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.envs (id, created_at, updated_at, public, build_count, spawn_count, last_spawned_at, team_id, created_by, cluster_id, source) FROM stdin;
0y5wsbhhevg9ajcsthpb	2026-04-25 22:30:14.612431+00	2026-04-25 22:30:14.612431+00	f	1	0	\N	ff47822c-6a46-4f2b-adf5-66a402980f62	\N	\N	template
upoql7xdcpxelhvkztd8	2026-04-25 06:13:35.126526+00	2026-04-25 06:33:47.771322+00	f	9	62	2026-04-28 10:48:10.474569+00	ff47822c-6a46-4f2b-adf5-66a402980f62	\N	\N	template
\.


--
-- Data for Name: snapshot_templates; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.snapshot_templates (env_id, sandbox_id, created_at, origin_node_id, build_id) FROM stdin;
\.


--
-- Data for Name: snapshots; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.snapshots (created_at, env_id, sandbox_id, id, metadata, base_env_id, sandbox_started_at, env_secure, origin_node_id, allow_internet_access, auto_pause, team_id, config) FROM stdin;
\.


--
-- Data for Name: sutekh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.sutekh (id, created_at) FROM stdin;
\.


--
-- Data for Name: team_api_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.team_api_keys (created_at, team_id, updated_at, name, last_used, created_by, id, api_key_hash, api_key_prefix, api_key_length, api_key_mask_prefix, api_key_mask_suffix) FROM stdin;
2026-04-25 06:10:01.575276+00	ff47822c-6a46-4f2b-adf5-66a402980f62	2026-04-25 06:10:01.575276+00	Seed API Key	2026-04-28 10:48:10.406401+00	9c5250da-12b9-4d22-bab8-ccc4c625f35e	d81dfcde-6dce-47e5-a93a-b0735e503c7c	$sha256$OazH2jL6a+jIGIy74veP97NisMNnofUFWySJ+tmJAH0	e2b_	40	20	49eb
\.


--
-- Data for Name: teams; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.teams (id, created_at, is_blocked, name, tier, email, is_banned, blocked_reason, cluster_id, slug, sandbox_scheduling_labels) FROM stdin;
44d02ca0-a1b3-45ba-8f7e-505f59cbcb44	2026-04-24 22:53:49.710499+00	f	system@e2b.dev	base_v1	system@e2b.dev	f	\N	\N	system	{}
ff47822c-6a46-4f2b-adf5-66a402980f62	2026-04-25 06:10:01.513115+00	f	E2B	base_v1	admin@datacards.dev	f	\N	\N	e2b	{}
1ad0852e-f70a-43ab-9b22-ee1458a3aed6	2026-04-30 10:12:07.125812+00	f	nuclei-test-3d4acfkwrmktj85jxcwsohbbpsf@example.com	base_v1	nuclei-test-3d4acfkwrmktj85jxcwsohbbpsf@example.com	f	\N	\N	nuclei-test-3d4acfkwrmktj85jxcwsohbbpsf	{}
\.


--
-- Data for Name: tiers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tiers (id, name, disk_mb, concurrent_instances, max_length_hours, max_vcpu, max_ram_mb, concurrent_template_builds) FROM stdin;
base_v1	Base tier	512	20	1	8	8192	20
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.users (created_at, updated_at, id, email) FROM stdin;
2026-04-24 22:53:49.889991+00	2026-04-24 22:53:49.889991+00	00000000-0000-0000-0000-000000000000	system@e2b.dev
2026-04-25 06:10:01.459921+00	2026-04-25 06:10:01.459921+00	9c5250da-12b9-4d22-bab8-ccc4c625f35e	admin@datacards.dev
2026-04-30 10:12:07.125812+00	2026-04-30 10:12:07.125812+00	221217d4-d789-43d9-a34c-421709a45fb9	nuclei-test-3d4acfkwrmktj85jxcwsohbbpsf@example.com
2026-06-22 13:33:24.039978+00	2026-06-22 13:33:24.039978+00	ff654ddd-971b-4831-b6e1-3752f1fb4089	felix.koppe@cavorit.de
2026-06-22 13:33:41.637168+00	2026-06-22 13:33:41.637168+00	58af062e-5f5c-4174-966d-6a2855ad3db6	admin@cavorit.de
\.


--
-- Data for Name: users_teams; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.users_teams (id, user_id, team_id, is_default, added_by, created_at, uuid_id) FROM stdin;
1	00000000-0000-0000-0000-000000000000	44d02ca0-a1b3-45ba-8f7e-505f59cbcb44	t	\N	2026-04-24 22:53:49.710499	d3aa60be-17ff-421e-a4ab-1031b8a91e83
3	9c5250da-12b9-4d22-bab8-ccc4c625f35e	ff47822c-6a46-4f2b-adf5-66a402980f62	t	\N	2026-04-25 06:10:01.533283	68274a93-d14f-43d9-a429-17bff401f931
4	221217d4-d789-43d9-a34c-421709a45fb9	1ad0852e-f70a-43ab-9b22-ee1458a3aed6	t	\N	2026-04-30 10:12:07.125812	ad0f5b37-1bc4-4b18-b5ba-33082ea50bed
\.


--
-- Data for Name: volumes; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.volumes (id, team_id, name, volume_type, created_at) FROM stdin;
\.


--
-- Name: _migrations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public._migrations_id_seq', 97, true);


--
-- Name: sutekh_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.sutekh_id_seq', 1, false);


--
-- Name: users_teams_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.users_teams_id_seq', 6, true);


--
-- Name: _migrations _migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public._migrations
    ADD CONSTRAINT _migrations_pkey PRIMARY KEY (id);


--
-- Name: access_tokens access_tokens_access_token_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_tokens
    ADD CONSTRAINT access_tokens_access_token_hash_key UNIQUE (access_token_hash);


--
-- Name: access_tokens access_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_tokens
    ADD CONSTRAINT access_tokens_pkey PRIMARY KEY (id);


--
-- Name: active_template_builds active_template_builds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_template_builds
    ADD CONSTRAINT active_template_builds_pkey PRIMARY KEY (build_id);


--
-- Name: addons addons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.addons
    ADD CONSTRAINT addons_pkey PRIMARY KEY (id);


--
-- Name: clusters clusters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clusters
    ADD CONSTRAINT clusters_pkey PRIMARY KEY (id);


--
-- Name: env_aliases env_aliases_uuid_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.env_aliases
    ADD CONSTRAINT env_aliases_uuid_pkey PRIMARY KEY (id);


--
-- Name: env_build_assignments env_build_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.env_build_assignments
    ADD CONSTRAINT env_build_assignments_pkey PRIMARY KEY (id);


--
-- Name: env_builds env_builds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.env_builds
    ADD CONSTRAINT env_builds_pkey PRIMARY KEY (id);


--
-- Name: envs envs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.envs
    ADD CONSTRAINT envs_pkey PRIMARY KEY (id);


--
-- Name: snapshot_templates snapshot_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.snapshot_templates
    ADD CONSTRAINT snapshot_templates_pkey PRIMARY KEY (env_id);


--
-- Name: snapshots snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.snapshots
    ADD CONSTRAINT snapshots_pkey PRIMARY KEY (id);


--
-- Name: snapshots snapshots_sandbox_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.snapshots
    ADD CONSTRAINT snapshots_sandbox_id_unique UNIQUE (sandbox_id);


--
-- Name: sutekh sutekh_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sutekh
    ADD CONSTRAINT sutekh_pkey PRIMARY KEY (id);


--
-- Name: team_api_keys team_api_keys_api_key_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_api_keys
    ADD CONSTRAINT team_api_keys_api_key_hash_key UNIQUE (api_key_hash);


--
-- Name: team_api_keys team_api_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_api_keys
    ADD CONSTRAINT team_api_keys_pkey PRIMARY KEY (id);


--
-- Name: teams teams_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_pkey PRIMARY KEY (id);


--
-- Name: teams teams_slug_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_slug_unique UNIQUE (slug);


--
-- Name: tiers tiers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tiers
    ADD CONSTRAINT tiers_pkey PRIMARY KEY (id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users_teams users_teams_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_teams
    ADD CONSTRAINT users_teams_pkey PRIMARY KEY (uuid_id);


--
-- Name: volumes volumes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.volumes
    ADD CONSTRAINT volumes_pkey PRIMARY KEY (id);


--
-- Name: volumes volumes_teams_uq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.volumes
    ADD CONSTRAINT volumes_teams_uq UNIQUE (team_id, name);


--
-- Name: addons_idempotency_key_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX addons_idempotency_key_uidx ON public.addons USING btree (idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: addons_team_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX addons_team_id_idx ON public.addons USING btree (team_id);


--
-- Name: envs_cluster_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX envs_cluster_id ON public.envs USING btree (cluster_id) WHERE (cluster_id IS NOT NULL);


--
-- Name: idx_access_tokens_access_token_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_access_tokens_access_token_hash ON public.access_tokens USING btree (access_token_hash);


--
-- Name: idx_active_template_builds_team_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_active_template_builds_team_created_at ON public.active_template_builds USING btree (team_id, created_at DESC);


--
-- Name: idx_env_aliases_alias_namespace_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_env_aliases_alias_namespace_unique ON public.env_aliases USING btree (alias, namespace) NULLS NOT DISTINCT;


--
-- Name: idx_env_build_assignments_build; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_env_build_assignments_build ON public.env_build_assignments USING btree (build_id);


--
-- Name: idx_env_build_assignments_env_tag_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_env_build_assignments_env_tag_created ON public.env_build_assignments USING btree (env_id, tag, created_at DESC);


--
-- Name: idx_env_builds_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_env_builds_status ON public.env_builds USING btree (status);


--
-- Name: idx_env_builds_status_group; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_env_builds_status_group ON public.env_builds USING btree (status_group);


--
-- Name: idx_env_builds_team_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_env_builds_team_active ON public.env_builds USING btree (team_id) WHERE (status_group = ANY (ARRAY['pending'::text, 'in_progress'::text]));


--
-- Name: idx_env_builds_team_env_created_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_env_builds_team_env_created_id ON public.env_builds USING btree (team_id, env_id, created_at DESC, id DESC);


--
-- Name: idx_env_builds_team_status_group; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_env_builds_team_status_group ON public.env_builds USING btree (team_id, status_group);


--
-- Name: idx_env_builds_team_status_pagination; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_env_builds_team_status_pagination ON public.env_builds USING btree (team_id, created_at DESC, id DESC) INCLUDE (status, status_group);


--
-- Name: idx_envs_envs_aliases; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_envs_envs_aliases ON public.env_aliases USING btree (env_id);


--
-- Name: idx_envs_team_id_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_envs_team_id_source ON public.envs USING btree (team_id, source);


--
-- Name: idx_snapshot_templates_sandbox_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_snapshot_templates_sandbox_id ON public.snapshot_templates USING btree (sandbox_id);


--
-- Name: idx_snapshots_env_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_snapshots_env_id ON public.snapshots USING btree (env_id);


--
-- Name: idx_snapshots_sandbox_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_snapshots_sandbox_id ON public.snapshots USING btree (sandbox_id);


--
-- Name: idx_snapshots_team_metadata_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_snapshots_team_metadata_gin ON public.snapshots USING gin (team_id, metadata);


--
-- Name: idx_snapshots_team_time_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_snapshots_team_time_id ON public.snapshots USING btree (team_id, sandbox_started_at DESC, sandbox_id);


--
-- Name: idx_team_api_keys_api_key_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_team_api_keys_api_key_hash ON public.team_api_keys USING btree (api_key_hash);


--
-- Name: idx_team_team_api_keys; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_team_team_api_keys ON public.team_api_keys USING btree (team_id);


--
-- Name: idx_teams_user_teams; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_teams_user_teams ON public.users_teams USING btree (team_id);


--
-- Name: idx_users_access_tokens; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_access_tokens ON public.access_tokens USING btree (user_id);


--
-- Name: idx_users_user_teams; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_user_teams ON public.users_teams USING btree (user_id);


--
-- Name: snapshots_base_env_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX snapshots_base_env_id_idx ON public.snapshots USING btree (base_env_id);


--
-- Name: teams_cluster_id_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX teams_cluster_id_uq ON public.teams USING btree (cluster_id) WHERE (cluster_id IS NOT NULL);


--
-- Name: uq_legacy_assignments; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_legacy_assignments ON public.env_build_assignments USING btree (env_id, build_id, tag) WHERE (source = ANY (ARRAY['trigger'::text, 'migration'::text]));


--
-- Name: usersteams_team_id_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX usersteams_team_id_user_id ON public.users_teams USING btree (team_id, user_id);


--
-- Name: users post_user_signup; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER post_user_signup AFTER INSERT ON public.users FOR EACH ROW EXECUTE FUNCTION public.post_user_signup();


--
-- Name: teams team_slug_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER team_slug_trigger BEFORE INSERT ON public.teams FOR EACH ROW EXECUTE FUNCTION public.generate_team_slug_trigger();


--
-- Name: env_builds trg_compute_status_group; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_compute_status_group BEFORE INSERT OR UPDATE OF status ON public.env_builds FOR EACH ROW EXECUTE FUNCTION public.compute_status_group();


--
-- Name: snapshots trg_snapshots_fix_json_null_metadata; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_snapshots_fix_json_null_metadata BEFORE INSERT OR UPDATE OF metadata ON public.snapshots FOR EACH ROW EXECUTE FUNCTION public.fix_snapshots_metadata_json_null();


--
-- Name: snapshots trg_sync_env_source_on_snapshot; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_env_source_on_snapshot AFTER INSERT ON public.snapshots FOR EACH ROW EXECUTE FUNCTION public.sync_env_source_on_snapshot_insert();


--
-- Name: env_build_assignments trigger_backfill_env_id; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_backfill_env_id AFTER INSERT ON public.env_build_assignments FOR EACH ROW EXECUTE FUNCTION public.backfill_env_id_from_assignment();


--
-- Name: env_build_assignments trigger_backfill_team_id; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_backfill_team_id AFTER INSERT ON public.env_build_assignments FOR EACH ROW EXECUTE FUNCTION public.backfill_team_id_from_assignment();


--
-- Name: access_tokens access_tokens_users_access_tokens; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_tokens
    ADD CONSTRAINT access_tokens_users_access_tokens FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: addons addons_teams_addons; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.addons
    ADD CONSTRAINT addons_teams_addons FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE CASCADE;


--
-- Name: addons addons_users_addons; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.addons
    ADD CONSTRAINT addons_users_addons FOREIGN KEY (added_by) REFERENCES public.users(id);


--
-- Name: env_aliases env_aliases_envs_env_aliases; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.env_aliases
    ADD CONSTRAINT env_aliases_envs_env_aliases FOREIGN KEY (env_id) REFERENCES public.envs(id) ON DELETE CASCADE;


--
-- Name: envs envs_cluster_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.envs
    ADD CONSTRAINT envs_cluster_id_fkey FOREIGN KEY (cluster_id) REFERENCES public.clusters(id);


--
-- Name: envs envs_teams_envs; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.envs
    ADD CONSTRAINT envs_teams_envs FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: envs envs_users_created_envs; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.envs
    ADD CONSTRAINT envs_users_created_envs FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: env_build_assignments fk_env_build_assignments_build; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.env_build_assignments
    ADD CONSTRAINT fk_env_build_assignments_build FOREIGN KEY (build_id) REFERENCES public.env_builds(id) ON DELETE CASCADE;


--
-- Name: env_build_assignments fk_env_build_assignments_env; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.env_build_assignments
    ADD CONSTRAINT fk_env_build_assignments_env FOREIGN KEY (env_id) REFERENCES public.envs(id) ON DELETE CASCADE;


--
-- Name: snapshots fk_snapshots_team; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.snapshots
    ADD CONSTRAINT fk_snapshots_team FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: volumes fk_volumes_teams; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.volumes
    ADD CONSTRAINT fk_volumes_teams FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: snapshot_templates snapshot_templates_env_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.snapshot_templates
    ADD CONSTRAINT snapshot_templates_env_id_fkey FOREIGN KEY (env_id) REFERENCES public.envs(id) ON DELETE CASCADE;


--
-- Name: snapshots snapshots_envs_base_env_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.snapshots
    ADD CONSTRAINT snapshots_envs_base_env_id FOREIGN KEY (base_env_id) REFERENCES public.envs(id) ON DELETE CASCADE;


--
-- Name: snapshots snapshots_envs_env_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.snapshots
    ADD CONSTRAINT snapshots_envs_env_id FOREIGN KEY (env_id) REFERENCES public.envs(id) ON DELETE CASCADE;


--
-- Name: team_api_keys team_api_keys_teams_team_api_keys; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_api_keys
    ADD CONSTRAINT team_api_keys_teams_team_api_keys FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE CASCADE;


--
-- Name: team_api_keys team_api_keys_users_created_api_keys; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_api_keys
    ADD CONSTRAINT team_api_keys_users_created_api_keys FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: teams teams_cluster_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_cluster_id_fkey FOREIGN KEY (cluster_id) REFERENCES public.clusters(id);


--
-- Name: teams teams_tiers_teams; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_tiers_teams FOREIGN KEY (tier) REFERENCES public.tiers(id);


--
-- Name: users_teams users_teams_added_by_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_teams
    ADD CONSTRAINT users_teams_added_by_user FOREIGN KEY (added_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: users_teams users_teams_teams_teams; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_teams
    ADD CONSTRAINT users_teams_teams_teams FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE CASCADE;


--
-- Name: users_teams users_teams_users_users; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_teams
    ADD CONSTRAINT users_teams_users_users FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: team_api_keys Allow selection for users that are in the team; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow selection for users that are in the team" ON public.team_api_keys FOR SELECT TO authenticated USING ((auth.uid() IN ( SELECT users_teams.user_id
   FROM public.users_teams
  WHERE (users_teams.team_id = team_api_keys.team_id))));


--
-- Name: teams Allow selection for users that are in the team; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow selection for users that are in the team" ON public.teams FOR SELECT TO authenticated USING ((auth.uid() IN ( SELECT users_teams.user_id
   FROM public.users_teams
  WHERE (users_teams.team_id = teams.id))));


--
-- Name: users Allow to create a new user; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow to create a new user" ON public.users FOR INSERT TO trigger_user WITH CHECK (true);


--
-- Name: team_api_keys Allow to create a team api key to new user; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow to create a team api key to new user" ON public.team_api_keys FOR INSERT TO trigger_user WITH CHECK (true);


--
-- Name: teams Allow to create a team to new user; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow to create a team to new user" ON public.teams FOR INSERT TO trigger_user WITH CHECK (true);


--
-- Name: users_teams Allow to create a user team connection to new user; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow to create a user team connection to new user" ON public.users_teams FOR INSERT TO trigger_user WITH CHECK (true);


--
-- Name: access_tokens Allow to create an access token to new user; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow to create an access token to new user" ON public.access_tokens FOR INSERT TO trigger_user WITH CHECK (true);


--
-- Name: users Allow to delete a user; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow to delete a user" ON public.users FOR DELETE TO trigger_user USING (true);


--
-- Name: teams Allow to select a team for supabase auth admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow to select a team for supabase auth admin" ON public.teams FOR SELECT TO trigger_user USING (true);


--
-- Name: users Allow to select a user; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow to select a user" ON public.users FOR SELECT TO trigger_user USING (true);


--
-- Name: users Allow to update a user; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow to update a user" ON public.users FOR UPDATE TO trigger_user USING (true) WITH CHECK (true);


--
-- Name: team_api_keys Allow users to delete a team api key; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow users to delete a team api key" ON public.team_api_keys FOR DELETE TO authenticated USING ((( SELECT auth.uid() AS uid) IN ( SELECT users_teams.user_id
   FROM public.users_teams
  WHERE (users_teams.team_id = team_api_keys.team_id))));


--
-- Name: access_tokens Enable select for users based on user_id; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Enable select for users based on user_id" ON public.access_tokens FOR SELECT TO authenticated USING ((auth.uid() = user_id));


--
-- Name: users_teams Enable select for users in relevant team; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Enable select for users in relevant team" ON public.users_teams FOR SELECT TO authenticated USING (public.is_member_of_team(auth.uid(), team_id));


--
-- Name: _migrations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public._migrations ENABLE ROW LEVEL SECURITY;

--
-- Name: access_tokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.access_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: active_template_builds; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.active_template_builds ENABLE ROW LEVEL SECURITY;

--
-- Name: addons; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.addons ENABLE ROW LEVEL SECURITY;

--
-- Name: clusters; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.clusters ENABLE ROW LEVEL SECURITY;

--
-- Name: env_aliases; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.env_aliases ENABLE ROW LEVEL SECURITY;

--
-- Name: env_build_assignments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.env_build_assignments ENABLE ROW LEVEL SECURITY;

--
-- Name: env_builds; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.env_builds ENABLE ROW LEVEL SECURITY;

--
-- Name: envs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.envs ENABLE ROW LEVEL SECURITY;

--
-- Name: snapshot_templates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.snapshot_templates ENABLE ROW LEVEL SECURITY;

--
-- Name: snapshots; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.snapshots ENABLE ROW LEVEL SECURITY;

--
-- Name: sutekh; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sutekh ENABLE ROW LEVEL SECURITY;

--
-- Name: team_api_keys; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.team_api_keys ENABLE ROW LEVEL SECURITY;

--
-- Name: teams; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.teams ENABLE ROW LEVEL SECURITY;

--
-- Name: tiers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tiers ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- Name: users_teams; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.users_teams ENABLE ROW LEVEL SECURITY;

--
-- Name: volumes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.volumes ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

