-- migrations/11_name_cleanup_tier1_2.sql
-- Catalog name cleanup, SAFE TIERS ONLY. Runs in a transaction, defaults to
-- ROLLBACK (preview). To apply: comment ROLLBACK, uncomment COMMIT, re-run.
--
-- SCOPE (deliberately limited):
--   Tier 1 - pure renames (strip junk chars / garbage tails). No FK touch.
--   Tier 2 - delete ONE empty orphan fragment (0 skus/clin/dosing/inter/products).
-- OUT OF SCOPE (deferred to a later migration, needs manual SKU triage):
--   Tier 3 - the 7 numbered-list fusion rows that carry (dubious) SKUs.
--
-- Pre-checks done read-only 2026-06-24:
--   * downstream products on all target rows = 0
--   * no clean "Oxymetholone" row exists (rename won't create a dup)
--   * bceeac1b has 0 of everything

BEGIN;
SET LOCAL client_min_messages = NOTICE;

CREATE OR REPLACE FUNCTION pg_temp._id(pfx text) RETURNS uuid LANGUAGE sql AS
$id$ SELECT id FROM drug WHERE id::text LIKE pfx||'%' $id$;

-- prefix sanity (each resolves to exactly one row)
DO $chk$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('28856e04'),('b96da4ef'),('7c8cca4b'),('bceeac1b')
  ) AS t(pfx) LOOP
    IF (SELECT count(*) FROM drug WHERE id::text LIKE r.pfx||'%') <> 1 THEN
      RAISE EXCEPTION 'prefix % not unique', r.pfx;
    END IF;
  END LOOP;
END $chk$;

-- guard: renaming 7c8cca4b -> 'Oxymetholone' must not collide with an existing one
DO $g$
BEGIN
  IF EXISTS (SELECT 1 FROM drug WHERE inn_name = 'Oxymetholone'
                                   AND id <> pg_temp._id('7c8cca4b')) THEN
    RAISE EXCEPTION 'a clean Oxymetholone row already exists - handle as merge, not rename';
  END IF;
END $g$;

-- ---- Tier 1: renames ------------------------------------------------------
UPDATE drug SET inn_name = 'Ferrous Salt'
 WHERE id = pg_temp._id('28856e04');
UPDATE drug SET inn_name = 'Ferrous Salt + Folic Acid'
 WHERE id = pg_temp._id('b96da4ef');
UPDATE drug SET inn_name = 'Oxymetholone'
 WHERE id = pg_temp._id('7c8cca4b');

-- ---- Tier 2: delete empty orphan fragment ---------------------------------
-- Re-assert it's truly empty before deleting (defensive; cascade would fire
-- on any children, but there should be none).
DO $del$
DECLARE v_id uuid := pg_temp._id('bceeac1b');
DECLARE v_sku int; v_clin int; v_dose int; v_int int;
BEGIN
  SELECT count(*) INTO v_sku  FROM drug_sku            WHERE drug_id=v_id;
  SELECT count(*) INTO v_clin FROM clinical_reference  WHERE drug_id=v_id;
  SELECT count(*) INTO v_dose FROM dosing_guideline    WHERE drug_id=v_id;
  SELECT count(*) INTO v_int  FROM drug_interaction_cache
         WHERE drug_a_id=v_id OR drug_b_id=v_id;
  IF v_sku+v_clin+v_dose+v_int <> 0 THEN
    RAISE EXCEPTION 'bceeac1b not empty (sku:% clin:% dose:% int:%) - aborting delete',
      v_sku,v_clin,v_dose,v_int;
  END IF;
  DELETE FROM drug WHERE id=v_id;
  RAISE NOTICE 'deleted empty orphan bceeac1b';
END $del$;

-- ===========================================================================
-- PREVIEW
-- ===========================================================================
\echo === Renamed rows (no junk chars, expect clean ASCII names) ===
SELECT substr(id::text,1,8) AS id, inn_name,
       (inn_name ~ '[^[:ascii:]]') AS still_has_nonascii
FROM drug WHERE id::text LIKE ANY (ARRAY['28856e04%','b96da4ef%','7c8cca4b%']);

\echo === Orphan gone? (expect 0 rows) ===
SELECT count(*) AS bceeac1b_remaining FROM drug WHERE id::text LIKE 'bceeac1b%';

\echo === Remaining non-ASCII names overall (should drop from 9 toward fewer) ===
SELECT count(*) AS rows_with_non_ascii FROM drug WHERE inn_name ~ '[^[:ascii:]]';

-- ===========================================================================
-- SAFETY: defaults to ROLLBACK. To apply: comment ROLLBACK, uncomment COMMIT.
-- ===========================================================================
-- ROLLBACK;
COMMIT;
