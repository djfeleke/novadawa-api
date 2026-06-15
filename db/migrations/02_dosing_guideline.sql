-- =====================================================================
-- NovaDawa — Dosing Guideline Schema (migration 02)
-- =====================================================================
-- Adds weight-based and fixed-dose prescribing guidelines to the drug
-- catalog. Primary use case: pediatric weight-band dosing (like the
-- WHO Pocket Book tables), but the model is general enough for any
-- age-gated or weight-based dosing rule.
--
-- Apply order:  00_schema.sql → 01_tenant_schema.sql → 02_dosing_guideline.sql
--
-- Design decisions:
--   * FK to `drug` (not drug_sku) — dosing is a clinical concept per
--     active ingredient. The dispensing app picks the available SKU
--     and computes volume: volume_ml = per_dose_mg / concentration.
--   * Daily dose stored as mg/kg/day (the standard in WHO, BNFc,
--     Kinderformularium). Per-dose = daily / doses_per_day.
--   * Fixed-dose column for adult/flat-dose drugs (e.g. "250 mg TID
--     regardless of weight").
--   * max_single_dose_mg and max_daily_dose_mg enforce safety ceilings.
--   * age stored in months for precision (neonatal = 0, 3 months = 3,
--     6 years = 72, etc.).
--   * source + source_edition track provenance — critical for
--     regulatory credibility ("based on WHO Pocket Book 2013").
--   * One drug can have MANY guideline rows: different indications,
--     different age bands, different dose tiers (fever vs pain for
--     acetaminophen, strep vs other for azithromycin, etc.).
-- =====================================================================

-- Enum for route of administration
CREATE TYPE dose_route AS ENUM (
    'oral',
    'iv',
    'im',
    'sc',
    'topical',
    'rectal',
    'inhaled',
    'ophthalmic',
    'otic',
    'nasal',
    'sublingual'
);

-- Enum for common frequency abbreviations
CREATE TYPE dose_frequency AS ENUM (
    'STAT',       -- single dose
    'daily',      -- once daily (OD / QD)
    'BID',        -- twice daily
    'TID',        -- three times daily
    'QID',        -- four times daily
    'Q4H',        -- every 4 hours
    'Q6H',        -- every 6 hours
    'Q8H',        -- every 8 hours
    'Q12H',       -- every 12 hours
    'Q24H',       -- every 24 hours
    'PRN',        -- as needed
    'weekly',     -- once weekly
    'other'       -- freeform — see notes
);

-- Dosing guideline source registry (normalize repeated source names)
CREATE TABLE dosing_source (
    id              SERIAL PRIMARY KEY,
    name            VARCHAR(120) NOT NULL UNIQUE,
        -- e.g. 'WHO Pocket Book of Hospital Care for Children'
    edition         VARCHAR(60),
        -- e.g. '2nd Edition, 2013'
    url             TEXT,
        -- link to source document
    is_open_access  BOOLEAN NOT NULL DEFAULT false,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Main dosing guideline table
CREATE TABLE dosing_guideline (
    id                  SERIAL PRIMARY KEY,
    drug_id             UUID NOT NULL REFERENCES drug(id) ON DELETE CASCADE,
    source_id           INTEGER NOT NULL REFERENCES dosing_source(id),

    -- What is being treated
    indication          VARCHAR(200) NOT NULL,
        -- e.g. 'Fever', 'Pain', 'Strep pharyngitis', 'Acute otitis media',
        --       'Acute asthma', 'Cold sore', 'Mild-moderate anemia'

    -- Route
    route               dose_route NOT NULL DEFAULT 'oral',

    -- Patient eligibility window (NULL = no bound)
    age_min_months      SMALLINT CHECK (age_min_months >= 0),
    age_max_months      SMALLINT CHECK (age_max_months >= 0),
    weight_min_kg       NUMERIC(5,1) CHECK (weight_min_kg > 0),
    weight_max_kg       NUMERIC(5,1) CHECK (weight_max_kg > 0),

    -- Dose specification (exactly one of these two should be non-null)
    dose_mg_per_kg_day  NUMERIC(8,2),
        -- Total daily dose in mg per kg of body weight.
        -- e.g. Amoxicillin 90mg/kg/day → 90.00
        --      Acetaminophen 10mg/kg/dose TID → store as 30.00 (10 × 3)
    dose_fixed_mg       NUMERIC(8,2),
        -- Fixed daily dose in mg (weight-independent).
        -- e.g. Penicillin VK 250mg TID → store as 750.00

    -- Frequency
    frequency           dose_frequency NOT NULL,
    doses_per_day       SMALLINT NOT NULL CHECK (doses_per_day >= 1),
        -- Explicit count: BID=2, TID=3, QID=4, daily=1, etc.
        -- For PRN, store the max doses/day here.

    -- Safety ceilings
    max_single_dose_mg  NUMERIC(8,2),
        -- Hard ceiling per administration. e.g. ibuprofen max 400mg/dose
    max_daily_dose_mg   NUMERIC(8,2),
        -- Hard ceiling per day. e.g. acetaminophen max 4000mg/day

    -- Treatment duration
    duration_days       SMALLINT,
        -- Standard course length. NULL = ongoing/PRN.
        -- e.g. Azithromycin strep = 5, Penicillin VK strep = 10

    -- Day-specific dosing pattern (for loading doses etc.)
    -- e.g. Azithromycin "other infection": 10mg/kg day 1, then 5mg/kg days 2-5
    -- Stored as JSONB array: [{"days":"1","mg_per_kg_day":10},{"days":"2-5","mg_per_kg_day":5}]
    -- NULL means uniform dosing every day.
    day_pattern         JSONB,

    -- Formulation hint — helps the app pick the right SKU
    -- e.g. 'suspension', 'chewable tablet', 'injection'
    preferred_form      VARCHAR(60),

    -- Clinical notes shown to pharmacist at dispensing
    notes               TEXT,
        -- e.g. 'Only for children over 2 y/o'
        --       'Rub injection site after administration'
        --       'May repeat every 5-10 min up to 4 doses'

    is_pediatric        BOOLEAN NOT NULL DEFAULT true,
    is_active           BOOLEAN NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Ensure age range is valid when both are specified
    CONSTRAINT chk_age_range CHECK (
        age_min_months IS NULL OR age_max_months IS NULL
        OR age_min_months <= age_max_months
    ),
    -- Ensure weight range is valid when both are specified
    CONSTRAINT chk_weight_range CHECK (
        weight_min_kg IS NULL OR weight_max_kg IS NULL
        OR weight_min_kg <= weight_max_kg
    ),
    -- Ensure at least one dose type is specified
    CONSTRAINT chk_dose_specified CHECK (
        dose_mg_per_kg_day IS NOT NULL OR dose_fixed_mg IS NOT NULL
    )
);

-- =====================================================================
-- Indexes
-- =====================================================================

-- Primary lookup: "show me all dosing guidelines for drug X"
CREATE INDEX idx_dosing_guideline_drug
    ON dosing_guideline(drug_id);

-- Filter by indication (pharmacist searching "strep" dosing)
CREATE INDEX idx_dosing_guideline_indication
    ON dosing_guideline USING gin (indication gin_trgm_ops);

-- Filter by age eligibility (app query: child is 18 months old)
CREATE INDEX idx_dosing_guideline_age
    ON dosing_guideline(age_min_months, age_max_months)
    WHERE is_active = true;

-- Pediatric-specific queries
CREATE INDEX idx_dosing_guideline_pediatric
    ON dosing_guideline(drug_id)
    WHERE is_pediatric = true AND is_active = true;

-- Source lookup
CREATE INDEX idx_dosing_guideline_source
    ON dosing_guideline(source_id);


-- =====================================================================
-- Seed: Dosing Sources
-- =====================================================================

INSERT INTO dosing_source (name, edition, url, is_open_access, notes) VALUES
('WHO Pocket Book of Hospital Care for Children',
 '2nd Edition, 2013',
 'https://www.who.int/publications/i/item/978-92-4-154837-3',
 true,
 'Weight-band dosing tables for common pediatric drugs. Freely available.'),

('WHO EMLc Antibiotic Dosing Consensus',
 '2017',
 'https://cdn.who.int/media/docs/default-source/essential-medicines/2019-eml-expert-committee/late-papers/abwg_paediatric_dosing_ab.pdf',
 true,
 'Harmonized antibiotic doses for EMLc-listed drugs.'),

('Ethiopian Essential Medicines List (EEML)',
 '2024',
 'https://www.efda.gov.et/wp-content/uploads/2025/02/Ethiopian-Essential-Medicines-List-Oct-2024.pdf',
 true,
 'Official EFDA essential medicines list for Ethiopia.'),

('SwissPedDose',
 '2024',
 'https://db.swisspeddose.ch/',
 true,
 'Swiss nationally harmonized pediatric dosing. Free XML download for institutions.'),

('Kinderformularium (Dutch Paediatric Formulary)',
 '2024',
 'https://www.kinderformularium.nl/',
 true,
 'Dutch evidence-based pediatric formulary. Free for healthcare professionals.');


-- =====================================================================
-- Seed: Sample Dosing Guidelines (from WHO + your uploaded chart)
-- =====================================================================
-- These cover the most common pediatric drugs dispensed at Ethiopian
-- community pharmacies. Source IDs reference the dosing_source rows above.
-- source_id = 1 → WHO Pocket Book
-- source_id = 2 → WHO EMLc Consensus
-- =====================================================================

INSERT INTO dosing_guideline (
    drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg,
    frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg,
    duration_days, day_pattern, preferred_form,
    notes, is_pediatric
) VALUES

-- ── Acetaminophen (Paracetamol) ─────────────────────────────────────
-- Match drug by name — replace with actual drug_id after lookup
-- For now using subselect: (SELECT id FROM drug WHERE inn_name ILIKE 'paracetamol%' LIMIT 1)

( (SELECT id FROM drug WHERE inn_name ILIKE 'paracetamol%' LIMIT 1),
  1, 'Fever', 'oral',
  2, NULL, NULL, NULL,
  40.00, NULL,           -- 10mg/kg/dose × QID = 40mg/kg/day
  'QID', 4,
  1000.00, 4000.00,
  NULL, NULL, 'suspension',
  'Dose per administration: 10mg/kg. Minimum age 2 months.', true ),

( (SELECT id FROM drug WHERE inn_name ILIKE 'paracetamol%' LIMIT 1),
  1, 'Pain', 'oral',
  2, NULL, NULL, NULL,
  60.00, NULL,           -- 15mg/kg/dose × QID = 60mg/kg/day
  'QID', 4,
  1000.00, 4000.00,
  NULL, NULL, 'suspension',
  'Dose per administration: 15mg/kg. Minimum age 2 months.', true ),

-- ── Amoxicillin ─────────────────────────────────────────────────────
( (SELECT id FROM drug WHERE inn_name ILIKE 'amoxicillin' LIMIT 1),
  1, 'Acute otitis media', 'oral',
  3, NULL, NULL, NULL,
  90.00, NULL,           -- 90mg/kg/day
  'BID', 2,
  2000.00, NULL,
  10, NULL, 'suspension',
  'High-dose amoxicillin. Standard 10-day course for AOM.', true ),

( (SELECT id FROM drug WHERE inn_name ILIKE 'amoxicillin' LIMIT 1),
  1, 'Strep pharyngitis', 'oral',
  3, NULL, NULL, NULL,
  90.00, NULL,
  'BID', 2,
  2000.00, NULL,
  10, NULL, 'suspension',
  'High-dose amoxicillin. 10-day course.', true ),

( (SELECT id FROM drug WHERE inn_name ILIKE 'amoxicillin' LIMIT 1),
  2, 'Community-acquired pneumonia', 'oral',
  3, NULL, NULL, NULL,
  80.00, NULL,           -- 80mg/kg/day per WHO
  'BID', 2,
  2000.00, NULL,
  5, NULL, 'suspension',
  'WHO-recommended for non-severe pneumonia. 5-day course.', true ),

-- ── Amoxicillin + Clavulanic Acid (Augmentin) ──────────────────────
( (SELECT id FROM drug WHERE inn_name ILIKE 'amoxicillin%clavulanic%' LIMIT 1),
  1, 'Recurrent acute otitis media', 'oral',
  3, NULL, NULL, NULL,
  90.00, NULL,           -- 90mg/kg/day (amoxicillin component)
  'BID', 2,
  2000.00, NULL,
  10, NULL, 'suspension',
  'Dose based on amoxicillin component. Use ES (600mg/5ml) formulation.', true ),

-- ── Azithromycin ────────────────────────────────────────────────────
( (SELECT id FROM drug WHERE inn_name ILIKE 'azithromycin%' LIMIT 1),
  1, 'Strep pharyngitis', 'oral',
  6, NULL, NULL, NULL,
  12.00, NULL,           -- 12mg/kg/day × 1 dose/day × 5 days (uniform)
  'daily', 1,
  500.00, 500.00,
  5, NULL, 'suspension',
  '12mg/kg once daily for 5 days. Max 500mg/dose.', true ),

( (SELECT id FROM drug WHERE inn_name ILIKE 'azithromycin%' LIMIT 1),
  1, 'Other bacterial infection', 'oral',
  6, NULL, NULL, NULL,
  NULL, NULL,            -- variable: day 1 ≠ days 2-5, use day_pattern
  'daily', 1,
  500.00, 500.00,
  5,
  '[{"days":"1","mg_per_kg_day":10},{"days":"2-5","mg_per_kg_day":5}]'::jsonb,
  'suspension',
  'Loading dose day 1 (10mg/kg) then 5mg/kg days 2-5.', true ),

-- ── Ibuprofen ───────────────────────────────────────────────────────
( (SELECT id FROM drug WHERE inn_name ILIKE 'ibuprofen%' LIMIT 1),
  1, 'Fever (< 102.5°F)', 'oral',
  6, NULL, NULL, NULL,
  20.00, NULL,           -- 5mg/kg/dose × QID = 20mg/kg/day
  'Q6H', 4,
  400.00, 1200.00,
  NULL, NULL, 'suspension',
  'Low-dose for mild fever. Minimum age 6 months.', true ),

( (SELECT id FROM drug WHERE inn_name ILIKE 'ibuprofen%' LIMIT 1),
  1, 'Fever (≥ 102.5°F) / Pain', 'oral',
  6, NULL, NULL, NULL,
  40.00, NULL,           -- 10mg/kg/dose × QID = 40mg/kg/day
  'Q6H', 4,
  400.00, 2400.00,
  NULL, NULL, 'suspension',
  'Higher dose for high fever or pain. Minimum age 6 months.', true ),

-- ── Cotrimoxazole (Sulfamethoxazole/Trimethoprim) ───────────────────
( (SELECT id FROM drug WHERE inn_name ILIKE '%trimethoprim%' OR name ILIKE '%cotrimoxazole%' LIMIT 1),
  1, 'UTI / Bacterial infection', 'oral',
  2, NULL, NULL, NULL,
  NULL, NULL,            -- 8-12mg TMP/kg/day — stored as range in notes
  'BID', 2,
  320.00, 640.00,
  NULL, NULL, 'suspension',
  'Dose based on TMP component: 8-12mg TMP/kg/day divided BID. See WHO weight-band table.', true ),

-- ── Cephalexin ──────────────────────────────────────────────────────
( (SELECT id FROM drug WHERE inn_name ILIKE 'cephalexin%' OR name ILIKE 'cefalexin%' LIMIT 1),
  1, 'Skin and soft tissue infection', 'oral',
  3, NULL, NULL, NULL,
  100.00, NULL,          -- 100mg/kg/day
  'TID', 3,
  2000.00, NULL,
  7, NULL, 'suspension',
  '100mg/kg/day divided TID.', true ),

-- ── Metronidazole ───────────────────────────────────────────────────
( (SELECT id FROM drug WHERE inn_name ILIKE 'metronidazole%' LIMIT 1),
  2, 'Amoebiasis / Giardiasis', 'oral',
  1, NULL, NULL, NULL,
  30.00, NULL,           -- 30mg/kg/day
  'TID', 3,
  500.00, 2000.00,
  7, NULL, 'suspension',
  '30mg/kg/day divided TID for 7 days.', true ),

-- ── Prednisolone ────────────────────────────────────────────────────
( (SELECT id FROM drug WHERE inn_name ILIKE 'prednisolone%' LIMIT 1),
  1, 'Acute asthma exacerbation', 'oral',
  3, NULL, NULL, NULL,
  2.00, NULL,            -- 1-2mg/kg/day (using high end)
  'daily', 1,
  60.00, 60.00,
  5, NULL, 'suspension',
  '1-2mg/kg/day for 3-5 days. Usually given as single morning dose.', true ),

-- ── ORS (Oral Rehydration Salts) ────────────────────────────────────
( (SELECT id FROM drug WHERE inn_name ILIKE '%oral rehydration%' OR name ILIKE 'ORS%' LIMIT 1),
  1, 'Mild-moderate dehydration', 'oral',
  0, NULL, NULL, NULL,
  NULL, NULL,
  'other', 1,
  NULL, NULL,
  NULL, NULL, NULL,
  'WHO Plan B: 75ml/kg over 4 hours. Reassess after each stool.', true ),

-- ── Zinc ────────────────────────────────────────────────────────────
( (SELECT id FROM drug WHERE inn_name ILIKE 'zinc%' LIMIT 1),
  1, 'Acute diarrhea (adjunct to ORS)', 'oral',
  0, 6, NULL, NULL,
  NULL, 10.00,           -- Fixed: 10mg/day for infants < 6 months
  'daily', 1,
  10.00, 10.00,
  14, NULL, 'suspension',
  'WHO: 10mg/day for children < 6 months. Continue for 14 days.', true ),

( (SELECT id FROM drug WHERE inn_name ILIKE 'zinc%' LIMIT 1),
  1, 'Acute diarrhea (adjunct to ORS)', 'oral',
  6, NULL, NULL, NULL,
  NULL, 20.00,           -- Fixed: 20mg/day for children ≥ 6 months
  'daily', 1,
  20.00, 20.00,
  14, NULL, 'suspension',
  'WHO: 20mg/day for children ≥ 6 months. Continue for 14 days.', true );


-- =====================================================================
-- Helper view: per-dose breakdown for dispensing UI
-- =====================================================================
-- The app queries this view with (drug_id, patient_age_months,
-- patient_weight_kg) and gets back the per-dose amount in mg,
-- which it then divides by the available SKU concentration to get ml.
-- =====================================================================

CREATE OR REPLACE VIEW v_dosing_per_dose AS
SELECT
    dg.id                   AS guideline_id,
    dg.drug_id,
    d.inn_name                  AS drug_name,
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
    -- Per-dose calculation:
    -- If weight-based: per_dose_mg_per_kg = daily / doses_per_day
    -- Multiply by patient weight at query time in the app.
    CASE
        WHEN dg.dose_mg_per_kg_day IS NOT NULL
        THEN ROUND(dg.dose_mg_per_kg_day / dg.doses_per_day, 2)
        ELSE NULL
    END                     AS per_dose_mg_per_kg,
    -- If fixed dose: per_dose_mg = daily / doses_per_day
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


-- =====================================================================
-- Example app query (not executed — reference for FastAPI endpoint):
-- =====================================================================
--
--   -- "Child is 14 months old, weighs 10kg, prescribed amoxicillin"
--   SELECT
--       v.*,
--       COALESCE(
--          LEAST(v.per_dose_mg_per_kg * 10.0, v.max_single_dose_mg),
--          LEAST(v.per_dose_fixed_mg, v.max_single_dose_mg)
--       ) AS per_dose_mg,
--       -- Then in Python: per_dose_ml = per_dose_mg / sku_concentration_mg_per_ml
--   FROM v_dosing_per_dose v
--   WHERE v.drug_name ILIKE '%amoxicillin%'
--     AND (v.age_min_months IS NULL OR v.age_min_months <= 14)
--     AND (v.age_max_months IS NULL OR v.age_max_months >= 14);
--
-- =====================================================================
