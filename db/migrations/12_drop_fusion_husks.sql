-- migrations/12_drop_fusion_husks.sql
-- Delete 7 numbered-list fusion husk drug rows and their synthetic seed SKUs.
-- Runs in a transaction, defaults to ROLLBACK (preview). Apply: swap to COMMIT.
--
-- EVIDENCE these SKUs are synthetic (not real product data), gathered 2026-06-24:
--   * all 27 SKUs share one microsecond timestamp 2026-06-08 00:34:04.483808+00
--   * all efda_approved=f, manufacturer/reg_number/route empty, vote_count=0,
--     submitted_by_group_id null -> zero provenance
--   * strength/form combos systematically implausible (Vincristine 30mg Capsule,
--     Carboplatin 20mg Ointment, "Express Tube", NaCl 600mg Tablet)
--   * clean standalone rows for each real drug already exist
--   * downstream products = 0 (re-asserted by guard below)
--
-- Husks (and the real standalone row that survives):
--   0c3285b8 Carboplatin/Carmustine     -> Carboplatin 7c9db6d0, Carmustine (sep)
--   3721c9af Etoposide/Fludarabine      -> Etoposide a22b1518, Fludarabine 8ab81755
--   5eb396f4 Express Tube/5-FU          -> Fluorouracil b97b263c
--   49c71ba5 Fluorouracil/Gemcitabine   -> Fluorouracil b97b263c, Gemcitabine 6e9f5f22
--   8c280470 Vincristine/Vinorelbine    -> Vincristine 4fcfa51b, Vinorelbine 1a6d4865
--   b09eca75 Sodium Chloride (+combo)   -> Sodium Chloride 0941b6dc
--   ae368c11 Darrow's/Hartmann's        -> (Lactated Ringer's exists: f093a717 related)

BEGIN;
SET LOCAL client_min_messages = NOTICE;

CREATE OR REPLACE FUNCTION pg_temp._id(pfx text) RETURNS uuid LANGUAGE sql AS
$id$ SELECT id FROM drug WHERE id::text LIKE pfx||'%' $id$;

-- The 7 husk drug ids (resolved, each must be unique).
CREATE TEMP TABLE _husks(id uuid) ON COMMIT DROP;
DO $load$
DECLARE p text; v uuid;
BEGIN
  FOREACH p IN ARRAY ARRAY['0c3285b8','3721c9af','5eb396f4','49c71ba5','8c280470','b09eca75','ae368c11']
  LOOP
    IF (SELECT count(*) FROM drug WHERE id::text LIKE p||'%') <> 1 THEN
      RAISE EXCEPTION 'husk prefix % not unique/found', p;
    END IF;
    SELECT id INTO v FROM drug WHERE id::text LIKE p||'%';
    INSERT INTO _husks VALUES (v);
  END LOOP;
END $load$;

-- ---- HARD GUARD: abort if ANY downstream reference exists on these SKUs -----
DO $guard$
DECLARE v_prod int; v_nreg int; v_nrev int;
BEGIN
  SELECT count(*) INTO v_prod FROM product p
    WHERE p.drug_sku_id IN (SELECT s.id FROM drug_sku s JOIN _husks h ON s.drug_id=h.id);
  SELECT count(*) INTO v_nreg FROM narcotics_register n
    WHERE n.drug_sku_id IN (SELECT s.id FROM drug_sku s JOIN _husks h ON s.drug_id=h.id);
  SELECT count(*) INTO v_nrev FROM narcotics_reversal n
    WHERE n.drug_sku_id IN (SELECT s.id FROM drug_sku s JOIN _husks h ON s.drug_id=h.id);
  IF v_prod + v_nreg + v_nrev <> 0 THEN
    RAISE EXCEPTION 'downstream refs present (product:% nreg:% nrev:%) - ABORT, SKUs are load-bearing',
      v_prod, v_nreg, v_nrev;
  END IF;
  RAISE NOTICE 'guard passed: 0 downstream refs (product/narcotics_register/narcotics_reversal)';
END $guard$;

-- ---- SAFETY GUARD: confirm none of the SKUs deviate from the synthetic batch -
-- If any SKU has real provenance (a manufacturer, reg number, a different
-- timestamp, or votes), STOP and re-evaluate by hand.
DO $prov$
DECLARE v_real int;
BEGIN
  SELECT count(*) INTO v_real
  FROM drug_sku s JOIN _husks h ON s.drug_id=h.id
  WHERE s.manufacturer IS NOT NULL
     OR s.efda_registration_number IS NOT NULL
     OR s.submitted_by_group_id IS NOT NULL
     OR s.approval_vote_count > 0
     OR s.created_at <> timestamptz '2026-06-08 00:34:04.483808+00';
  IF v_real <> 0 THEN
    RAISE EXCEPTION '% SKU(s) have real provenance or differ from the synthetic batch - ABORT, triage by hand', v_real;
  END IF;
  RAISE NOTICE 'provenance guard passed: all SKUs match the synthetic seed batch';
END $prov$;

-- ---- Delete (SKUs cascade via drug delete, but delete explicitly for count) -
WITH del_sku AS (
  DELETE FROM drug_sku s USING _husks h WHERE s.drug_id = h.id RETURNING s.id
)
SELECT count(*) AS skus_deleted FROM del_sku \gset
\echo skus_deleted = :skus_deleted

DELETE FROM drug d USING _husks h WHERE d.id = h.id;

-- ===========================================================================
-- PREVIEW
-- ===========================================================================
\echo === Husks gone? (expect 0) ===
SELECT count(*) AS husks_remaining FROM drug d JOIN _husks h ON d.id=h.id;

\echo === The real standalone rows still present? (expect all 8) ===
SELECT substr(id::text,1,8) AS id, inn_name,
       (SELECT count(*) FROM drug_sku s WHERE s.drug_id=d.id) AS skus
FROM drug d WHERE id::text LIKE ANY (ARRAY[
  '7c9db6d0%','a22b1518%','8ab81755%','b97b263c%','6e9f5f22%',
  '4fcfa51b%','1a6d4865%','0941b6dc%'])
ORDER BY inn_name;

\echo === No orphaned SKUs anywhere (expect 0) ===
SELECT count(*) AS orphan_skus FROM drug_sku s
WHERE NOT EXISTS (SELECT 1 FROM drug d WHERE d.id=s.drug_id);

\echo === Total drug count (was 1378 after mig 11; expect 1378-7 = 1371) ===
SELECT count(*) AS total_drugs FROM drug;

-- ===========================================================================
-- SAFETY: defaults to ROLLBACK. Apply: comment ROLLBACK, uncomment COMMIT.
-- ===========================================================================
-- ROLLBACK;
COMMIT;
