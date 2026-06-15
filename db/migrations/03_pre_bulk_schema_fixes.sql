-- =====================================================================
-- NovaDawa — Schema fixes required before bulk dosing seed (migration 03)
-- =====================================================================
-- These two changes were discovered while loading the bulk pediatric
-- dosing data and MUST run before 04_bulk_dosing_seed.sql.
--
-- 1. Relax chk_dose_specified: inhaled/topical/ophthalmic/otic/nasal
--    routes are dosed by puffs/application/drops, not mg/kg or fixed mg.
--    For these, dosing instructions live in the notes field.
--
-- 2. Widen dose columns NUMERIC(8,2) -> NUMERIC(12,2): unit-dosed drugs
--    like nystatin (400,000-2,000,000 units) overflow 8-digit precision.
--    The view must be dropped and recreated to alter the columns it uses.
--
-- Apply order:
--   00_schema.sql -> 01_tenant_schema.sql -> 02_dosing_guideline.sql
--   -> 03_pre_bulk_schema_fixes.sql -> 04_bulk_dosing_seed.sql
-- =====================================================================

-- ---------- Fix 1: relax dose-specified constraint ----------
ALTER TABLE dosing_guideline DROP CONSTRAINT chk_dose_specified;

ALTER TABLE dosing_guideline ADD CONSTRAINT chk_dose_specified CHECK (
    dose_mg_per_kg_day IS NOT NULL
    OR dose_fixed_mg IS NOT NULL
    OR route IN ('inhaled','topical','ophthalmic','otic','nasal')
);

-- ---------- Fix 2: widen dose columns for unit-dosed drugs ----------
DROP VIEW v_dosing_per_dose;

ALTER TABLE dosing_guideline
    ALTER COLUMN dose_fixed_mg       TYPE NUMERIC(12,2),
    ALTER COLUMN max_single_dose_mg  TYPE NUMERIC(12,2),
    ALTER COLUMN max_daily_dose_mg   TYPE NUMERIC(12,2),
    ALTER COLUMN dose_mg_per_kg_day  TYPE NUMERIC(12,2);

CREATE OR REPLACE VIEW v_dosing_per_dose AS
SELECT
    dg.id                   AS guideline_id,
    dg.drug_id,
    d.inn_name              AS drug_name,
    dg.indication,
    dg.route,
    dg.age_min_months,
    dg.age_max_months,
    dg.frequency,
    dg.doses_per_day,
    dg.duration_days,
    dg.preferred_form,
    dg.notes,
    ds.name                 AS source_name,
    ds.edition              AS source_edition,
    CASE
        WHEN dg.dose_mg_per_kg_day IS NOT NULL
        THEN ROUND(dg.dose_mg_per_kg_day / dg.doses_per_day, 2)
        ELSE NULL
    END                     AS per_dose_mg_per_kg,
    CASE
        WHEN dg.dose_fixed_mg IS NOT NULL
        THEN ROUND(dg.dose_fixed_mg / dg.doses_per_day, 2)
        ELSE NULL
    END                     AS per_dose_fixed_mg,
    dg.max_single_dose_mg,
    dg.max_daily_dose_mg,
    dg.day_pattern
FROM dosing_guideline dg
JOIN drug d ON d.id = dg.drug_id
JOIN dosing_source ds ON ds.id = dg.source_id
WHERE dg.is_active = true;
