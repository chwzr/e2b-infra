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
-- Data for Name: users; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, invited_at, confirmation_token, confirmation_sent_at, recovery_token, recovery_sent_at, email_change_token_new, email_change, email_change_sent_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, created_at, updated_at, phone, phone_confirmed_at, phone_change, phone_change_token, phone_change_sent_at, email_change_token_current, email_change_confirm_status, banned_until, reauthentication_token, reauthentication_sent_at, is_sso_user, deleted_at, is_anonymous) FROM stdin;
\N	00000000-0000-0000-0000-000000000000	\N	\N	system@e2b.dev	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N			\N		0	\N		\N	f	\N	f
\N	9c5250da-12b9-4d22-bab8-ccc4c625f35e	\N	\N	admin@datacards.dev	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	221217d4-d789-43d9-a34c-421709a45fb9	authenticated	authenticated	nuclei-test-3d4acfkwrmktj85jxcwsohbbpsf@example.com	$2a$10$rpVz4ytyKMK/gI6VpMLZl.K9m4B0jxEqXRDWvd7XEKagKHdFFnfUq	\N	\N		\N		\N			\N	\N	{"provider": "email", "providers": ["email"]}	{}	\N	2026-04-30 10:12:07.126363+00	2026-04-30 10:12:07.139403+00	\N	\N			\N		0	\N		\N	f	\N	f
\N	ff654ddd-971b-4831-b6e1-3752f1fb4089	\N	\N	felix.koppe@cavorit.de	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N			\N		0	\N		\N	f	\N	f
\N	58af062e-5f5c-4174-966d-6a2855ad3db6	\N	\N	admin@cavorit.de	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N			\N		0	\N		\N	f	\N	f
\.


--
-- PostgreSQL database dump complete
--

