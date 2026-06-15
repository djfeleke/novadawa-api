-- =====================================================================
-- NovaDawa — Catalog Cleanup (migration 05)
-- =====================================================================
-- One-time data-quality fixes applied after the bulk dosing seed.
--
-- 1. Deduplicate drug_sku: the seed inserted 263 duplicate SKU rows
--    (same drug_id + dosage_form + strength). Keeps one row per group.
-- 2. Add a UNIQUE constraint to prevent SKU duplicates recurring.
-- 3. Fix the "Zinc Sulphate GI 800Antiflatulents" parser artifact —
--    a merged name combining the drug, a category code, and the next
--    section header. Rename to clean "Zinc Sulphate" and remove an
--    empty duplicate zinc row that had no SKUs.
--
-- Apply order: ... -> 04_bulk_dosing_seed.sql -> 05_catalog_cleanup.sql
--
-- NOTE: This migration is idempotent-safe to skip on a fresh rebuild IF
-- the upstream seed files are themselves deduplicated. It is kept as a
-- historical record of fixes applied to the live database.
-- =====================================================================

-- ---------- Fix 1: deduplicate drug_sku ----------
DELETE FROM drug_sku ds
WHERE EXISTS (
  SELECT 1 FROM drug_sku keep
  WHERE keep.drug_id = ds.drug_id
    AND keep.dosage_form = ds.dosage_form
    AND keep.strength IS NOT DISTINCT FROM ds.strength
    AND keep.ctid < ds.ctid
);

-- ---------- Fix 2: prevent future SKU duplicates ----------
ALTER TABLE drug_sku
  ADD CONSTRAINT uq_drug_sku_drug_form_strength
  UNIQUE NULLS NOT DISTINCT (drug_id, dosage_form, strength);

-- ---------- Fix 3: zinc naming artifact ----------
-- Rename the data-bearing row (has the 2 pediatric SKUs + dosing rules)
UPDATE drug
SET inn_name = 'Zinc Sulphate'
WHERE inn_name = 'Zinc Sulphate GI 800Antiflatulents';

-- Remove the empty duplicate "Zinc Sulphate" row (no SKUs, no references).
-- Identified by having zero drug_sku children and General category.
DELETE FROM drug d
WHERE d.inn_name = 'Zinc Sulphate'
  AND d.therapeutic_category = 'General'
  AND NOT EXISTS (SELECT 1 FROM drug_sku WHERE drug_id = d.id)
  AND NOT EXISTS (SELECT 1 FROM dosing_guideline WHERE drug_id = d.id)
  AND NOT EXISTS (SELECT 1 FROM clinical_reference WHERE drug_id = d.id);
