CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TYPE public.aware_category AS ENUM ('Access', 'Watch', 'Reserve', 'Not_Classified');
CREATE TYPE public.dosage_form AS ENUM ('Tablet', 'Capsule', 'Syrup', 'Suspension', 'Solution', 'Injection', 'Infusion', 'Cream', 'Ointment', 'Gel', 'Lotion', 'Emulsion', 'Liquid', 'Elixir', 'Spray', 'Drop', 'Drops', 'Powder', 'Granules', 'Lozenge', 'Pessary', 'Suppository', 'Implant', 'Patch', 'Other');
CREATE TYPE public.interaction_severity AS ENUM ('minor', 'moderate', 'major', 'contraindicated');
CREATE TYPE public.registry_status AS ENUM ('pending', 'approved', 'rejected');


--
-- PostgreSQL database dump
--

\restrict NRjhwkGsgbAEhbzJxoBhhCKys5HwM3TNz6oMVroZHcyaVLNBN2zToMEcQxpeqhN

-- Dumped from database version 18.4 (48c2093)
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: clinical_reference; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clinical_reference (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    drug_id uuid NOT NULL,
    inn_name character varying(200) NOT NULL,
    indications text,
    dose_and_administration text,
    contraindications text,
    drug_interactions_text text,
    side_effects text,
    cautions text,
    storage_condition text,
    source character varying(50) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: drug; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.drug (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    inn_name character varying(200) NOT NULL,
    amharic_name character varying(200),
    pharmacological_class character varying(200),
    aware_category public.aware_category DEFAULT 'Not_Classified'::public.aware_category NOT NULL,
    atc_code character varying(20),
    therapeutic_category character varying(100),
    is_on_eeml boolean DEFAULT false NOT NULL,
    efda_registration_required boolean DEFAULT true NOT NULL,
    prescription_required boolean DEFAULT false NOT NULL,
    controlled_substance boolean DEFAULT false NOT NULL,
    is_community_pharmacy_approved boolean DEFAULT false NOT NULL,
    who_not_recommended boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: drug_interaction_cache; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.drug_interaction_cache (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    drug_a_id uuid NOT NULL,
    drug_b_id uuid NOT NULL,
    drug_a_name character varying(200) NOT NULL,
    drug_b_name character varying(200) NOT NULL,
    severity public.interaction_severity DEFAULT 'moderate'::public.interaction_severity NOT NULL,
    source character varying(50) NOT NULL,
    cached_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT drug_interaction_not_self CHECK ((drug_a_id <> drug_b_id))
);


--
-- Name: drug_sku; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.drug_sku (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    drug_id uuid NOT NULL,
    dosage_form public.dosage_form NOT NULL,
    strength character varying(150),
    base_unit character varying(20) NOT NULL,
    controlled_substance boolean DEFAULT false NOT NULL,
    efda_approved boolean DEFAULT false NOT NULL,
    is_vat_exempt boolean DEFAULT true NOT NULL,
    global_registry_status public.registry_status DEFAULT 'pending'::public.registry_status NOT NULL,
    manufacturer character varying(200),
    route_of_administration character varying(50),
    narcotic_class character varying(50),
    efda_registration_number character varying(100),
    efda_registration_expiry date,
    submitted_by_group_id uuid,
    approval_vote_count integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: clinical_reference clinical_reference_drug_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clinical_reference
    ADD CONSTRAINT clinical_reference_drug_id_key UNIQUE (drug_id);


--
-- Name: clinical_reference clinical_reference_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clinical_reference
    ADD CONSTRAINT clinical_reference_pkey PRIMARY KEY (id);


--
-- Name: drug_interaction_cache drug_interaction_cache_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drug_interaction_cache
    ADD CONSTRAINT drug_interaction_cache_pkey PRIMARY KEY (id);


--
-- Name: drug_interaction_cache drug_interaction_unique_pair; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drug_interaction_cache
    ADD CONSTRAINT drug_interaction_unique_pair UNIQUE (drug_a_id, drug_b_id);


--
-- Name: drug drug_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drug
    ADD CONSTRAINT drug_pkey PRIMARY KEY (id);


--
-- Name: drug_sku drug_sku_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drug_sku
    ADD CONSTRAINT drug_sku_pkey PRIMARY KEY (id);





--
-- Name: idx_drug_amharic_name_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_drug_amharic_name_trgm ON public.drug USING gin (amharic_name public.gin_trgm_ops);


--
-- Name: idx_drug_aware_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_drug_aware_category ON public.drug USING btree (aware_category);


--
-- Name: idx_drug_community_pharmacy; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_drug_community_pharmacy ON public.drug USING btree (is_community_pharmacy_approved);


--
-- Name: idx_drug_controlled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_drug_controlled ON public.drug USING btree (controlled_substance) WHERE (controlled_substance = true);


--
-- Name: idx_drug_inn_name_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_drug_inn_name_trgm ON public.drug USING gin (inn_name public.gin_trgm_ops);


--
-- Name: idx_drug_therapeutic_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_drug_therapeutic_category ON public.drug USING btree (therapeutic_category);


--
-- Name: idx_interaction_drug_a; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_interaction_drug_a ON public.drug_interaction_cache USING btree (drug_a_id);


--
-- Name: idx_interaction_drug_b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_interaction_drug_b ON public.drug_interaction_cache USING btree (drug_b_id);


--
-- Name: idx_sku_dosage_form; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sku_dosage_form ON public.drug_sku USING btree (dosage_form);


--
-- Name: idx_sku_drug_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sku_drug_id ON public.drug_sku USING btree (drug_id);


--
-- Name: clinical_reference clinical_reference_drug_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clinical_reference
    ADD CONSTRAINT clinical_reference_drug_id_fkey FOREIGN KEY (drug_id) REFERENCES public.drug(id) ON DELETE CASCADE;


--
-- Name: drug_interaction_cache drug_interaction_cache_drug_a_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drug_interaction_cache
    ADD CONSTRAINT drug_interaction_cache_drug_a_id_fkey FOREIGN KEY (drug_a_id) REFERENCES public.drug(id) ON DELETE CASCADE;


--
-- Name: drug_interaction_cache drug_interaction_cache_drug_b_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drug_interaction_cache
    ADD CONSTRAINT drug_interaction_cache_drug_b_id_fkey FOREIGN KEY (drug_b_id) REFERENCES public.drug(id) ON DELETE CASCADE;


--
-- Name: drug_sku drug_sku_drug_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drug_sku
    ADD CONSTRAINT drug_sku_drug_id_fkey FOREIGN KEY (drug_id) REFERENCES public.drug(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict NRjhwkGsgbAEhbzJxoBhhCKys5HwM3TNz6oMVroZHcyaVLNBN2zToMEcQxpeqhN

