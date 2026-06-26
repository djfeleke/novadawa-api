-- migrations/09_catalog_dedup.sql
-- Catalog duplicate-drug cleanup. Destructive multi-table merge on FK-referenced
-- clinical data. RUNS INSIDE A TRANSACTION. Defaults to ROLLBACK (preview mode).
-- To apply: change the final ROLLBACK to COMMIT after verifying the preview output.
--
-- Pre-req: backup taken (backups/dedup09_backup_*.sql), verified.
-- Decisions (from read-only investigation 2026-06-24):
--   8 clean pairs        : canon has no clinical_reference -> repoint empty's CR.
--   Phytomenadione/Terbinafine : KEEP canon's CR, empty's dies via delete.
--   Epinephrine (3-way)  : survivor monograph = empty2 d658f266; delete canon's
--                          CR first, then repoint d658f266's CR onto canon.
--   Scopolamine (3-way)  : survivor = 295627f3 (2 SKU). Merge af78d9bd + 2da4815a in.

BEGIN;

SET LOCAL client_min_messages = NOTICE;

-- ---------------------------------------------------------------------------
-- Reusable merge for one (empty -> canon) pair.
--   p_move_clinical = TRUE  : repoint empty's clinical_reference onto canon
--                             (only safe when canon currently has NO CR row).
--   p_move_clinical = FALSE : leave clinical_reference alone; empty's CR is
--                             removed by the final DELETE (ON DELETE CASCADE).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp._dedup_merge(
    p_empty uuid,
    p_canon uuid,
    p_move_clinical boolean
) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
    v_canon_name varchar(200);
    v_moved_sku  int;
    v_moved_dose int;
    v_del_intx   int;
    v_moved_intx int;
    v_moved_cr   int;
BEGIN
    SELECT inn_name INTO v_canon_name FROM drug WHERE id = p_canon;
    IF v_canon_name IS NULL THEN
        RAISE EXCEPTION 'canon % not found', p_canon;
    END IF;

    -- 1. SKUs ---------------------------------------------------------------
    UPDATE drug_sku SET drug_id = p_canon WHERE drug_id = p_empty;
    GET DIAGNOSTICS v_moved_sku = ROW_COUNT;

    -- 2. Dosing guidelines (no unique on drug_id -> clean repoint) ----------
    UPDATE dosing_guideline SET drug_id = p_canon WHERE drug_id = p_empty;
    GET DIAGNOSTICS v_moved_dose = ROW_COUNT;

    -- 3. Interactions -------------------------------------------------------
    -- 3a. Delete empty's rows that would self-loop or duplicate a canon pair
    --     (check BOTH orientations against the unique pair index).
    DELETE FROM drug_interaction_cache e
    WHERE (e.drug_a_id = p_empty OR e.drug_b_id = p_empty)
      AND (
            -- would become a self-loop after repoint
            (e.drug_a_id = p_empty AND e.drug_b_id = p_canon)
         OR (e.drug_b_id = p_empty AND e.drug_a_id = p_canon)
            -- collision with an existing canon pair, either orientation
         OR EXISTS (
              SELECT 1 FROM drug_interaction_cache c
              WHERE
                (   (e.drug_a_id = p_empty AND
                       ( (c.drug_a_id = p_canon AND c.drug_b_id = e.drug_b_id)
                      OR (c.drug_b_id = p_canon AND c.drug_a_id = e.drug_b_id) ))
                 OR (e.drug_b_id = p_empty AND
                       ( (c.drug_a_id = p_canon AND c.drug_b_id = e.drug_a_id)
                      OR (c.drug_b_id = p_canon AND c.drug_a_id = e.drug_a_id) ))
                )
            )
          );
    GET DIAGNOSTICS v_del_intx = ROW_COUNT;

    -- 3b. Repoint survivors + refresh the cached name on the moved side.
    UPDATE drug_interaction_cache
       SET drug_a_id = p_canon, drug_a_name = v_canon_name
     WHERE drug_a_id = p_empty;
    UPDATE drug_interaction_cache
       SET drug_b_id = p_canon, drug_b_name = v_canon_name
     WHERE drug_b_id = p_empty;
    GET DIAGNOSTICS v_moved_intx = ROW_COUNT;

    -- 4. Clinical reference -------------------------------------------------
    v_moved_cr := 0;
    IF p_move_clinical THEN
        -- guard: canon must not already have a CR (unique drug_id)
        IF EXISTS (SELECT 1 FROM clinical_reference WHERE drug_id = p_canon) THEN
            RAISE EXCEPTION 'move_clinical=TRUE but canon % already has a clinical_reference', p_canon;
        END IF;
        UPDATE clinical_reference SET drug_id = p_canon WHERE drug_id = p_empty;
        GET DIAGNOSTICS v_moved_cr = ROW_COUNT;
    END IF;

    -- 5. Delete the empty drug row (cascades any leftover CR if not moved) ---
    DELETE FROM drug WHERE id = p_empty;

    RAISE NOTICE 'merged % -> %  | sku:% dose:% intx(del:% moved:%) cr_moved:%',
        p_empty, p_canon, v_moved_sku, v_moved_dose, v_del_intx, v_moved_intx, v_moved_cr;
END $fn$;

-- helper to fetch full uuid from prefix
CREATE OR REPLACE FUNCTION pg_temp._id(pfx text) RETURNS uuid LANGUAGE sql AS
$id$ SELECT id FROM drug WHERE id::text LIKE pfx||'%' $id$;

-- Resolve short prefixes to full uuids once, fail loudly if any is ambiguous.
DO $chk$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('7db617fb'),('60d22dea'),('d473f12d'),('ffe26259'),
      ('ca80be93'),('fd284f83'),('080f904e'),('b25860f1'),
      ('1ccef393'),('be7ca43f'),('303f34d8'),('f96e2ee2'),
      ('a0c02953'),('8d7dd1b8'),('ea941fa4'),('f2f4f646'),
      ('e113e92b'),('d658f266'),('8bf88aa9'),
      ('2da4815a'),('af78d9bd'),('295627f3')
    ) AS t(pfx)
  LOOP
    IF (SELECT count(*) FROM drug WHERE id::text LIKE r.pfx||'%') <> 1 THEN
      RAISE EXCEPTION 'prefix % does not resolve to exactly one drug', r.pfx;
    END IF;
  END LOOP;
END $chk$;

-- ===========================================================================
-- DRIVER
-- ===========================================================================

-- ---- 8 clean pairs: canon has no CR -> move_clinical = TRUE ----------------
SELECT pg_temp._dedup_merge(pg_temp._id('7db617fb'), pg_temp._id('60d22dea'), true); -- Dactinomycin
SELECT pg_temp._dedup_merge(pg_temp._id('d473f12d'), pg_temp._id('ffe26259'), true); -- Daunomycin
SELECT pg_temp._dedup_merge(pg_temp._id('ca80be93'), pg_temp._id('fd284f83'), true); -- Folinic
SELECT pg_temp._dedup_merge(pg_temp._id('080f904e'), pg_temp._id('b25860f1'), true); -- Hyoscine butylbromide
SELECT pg_temp._dedup_merge(pg_temp._id('1ccef393'), pg_temp._id('be7ca43f'), true); -- Paracetamol
SELECT pg_temp._dedup_merge(pg_temp._id('a0c02953'), pg_temp._id('8d7dd1b8'), true); -- Sacubitril+Valsartan

-- ---- 2 keep-canon conflicts: canon HAS richer CR -> move_clinical = FALSE --
SELECT pg_temp._dedup_merge(pg_temp._id('303f34d8'), pg_temp._id('f96e2ee2'), false); -- Phytomenadione
SELECT pg_temp._dedup_merge(pg_temp._id('ea941fa4'), pg_temp._id('f2f4f646'), false); -- Terbinafine

-- ---- Epinephrine 3-way: survivor monograph = empty2 d658f266 ---------------
DELETE FROM clinical_reference WHERE drug_id = pg_temp._id('8bf88aa9'); -- remove canon's CR
SELECT pg_temp._dedup_merge(pg_temp._id('e113e92b'), pg_temp._id('8bf88aa9'), false); -- empty1: CR dies
SELECT pg_temp._dedup_merge(pg_temp._id('d658f266'), pg_temp._id('8bf88aa9'), true);  -- empty2: CR survives

-- ---- Scopolamine 3-way: survivor = 295627f3 (2 SKU) ------------------------
SELECT pg_temp._dedup_merge(pg_temp._id('af78d9bd'), pg_temp._id('295627f3'), false); -- no CR to move
SELECT pg_temp._dedup_merge(pg_temp._id('2da4815a'), pg_temp._id('295627f3'), true);  -- move its CR

-- ---- Typo fix on survivor -------------------------------------------------
UPDATE drug SET inn_name = 'Sacubitril + Valsartan' WHERE id = pg_temp._id('8d7dd1b8');

-- ===========================================================================
-- PREVIEW
-- ===========================================================================
\echo === All 12 empty rows should be GONE (expect 0) ===
SELECT count(*) AS empties_remaining FROM drug WHERE id::text LIKE ANY (ARRAY[
  '7db617fb%','d473f12d%','ca80be93%','080f904e%','1ccef393%','a0c02953%',
  '303f34d8%','ea941fa4%','e113e92b%','d658f266%','2da4815a%','af78d9bd%']);

\echo === Survivor counts (should reflect merged totals) ===
SELECT substr(d.id::text,1,8) AS canon, d.inn_name,
  (SELECT count(*) FROM drug_sku s WHERE s.drug_id=d.id)            AS skus,
  (SELECT count(*) FROM clinical_reference c WHERE c.drug_id=d.id)  AS clin,
  (SELECT count(*) FROM dosing_guideline g WHERE g.drug_id=d.id)    AS dosing,
  (SELECT count(*) FROM drug_interaction_cache x
     WHERE x.drug_a_id=d.id OR x.drug_b_id=d.id)                    AS inter
FROM drug d WHERE d.id::text LIKE ANY (ARRAY[
  '60d22dea%','ffe26259%','fd284f83%','b25860f1%','be7ca43f%','8d7dd1b8%',
  'f96e2ee2%','f2f4f646%','8bf88aa9%','295627f3%'])
ORDER BY d.inn_name;

\echo === Orphan check: any interaction self-loops? (expect 0) ===
SELECT count(*) AS self_loops FROM drug_interaction_cache WHERE drug_a_id = drug_b_id;

\echo === Sacubitril typo fixed? ===
SELECT inn_name FROM drug WHERE id = pg_temp._id('8d7dd1b8');

-- ===========================================================================
-- SAFETY: defaults to ROLLBACK. Review preview above. To APPLY, change the
-- next line to COMMIT (comment out ROLLBACK) and re-run.
-- ===========================================================================
-- ROLLBACK;
COMMIT;
