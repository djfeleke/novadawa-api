-- classify_controlled_substances.sql
-- ---------------------------------------------------------------------------
-- Populates drug_sku.narcotic_class ('narcotic' | 'psychotropic') and corrects
-- drug_sku.controlled_substance to match the EFDA National List of Psychotropic
-- Substances and Narcotic drugs (May 2017).
--
-- Classification is a property of the SUBSTANCE, so it is keyed off the parent
-- drug's inn_name and applied to ALL skus of that drug.
--
-- SAFETY: This file is in two parts.
--   PART A (SELECT only)  -> preview every change. Writes NOTHING. Run first.
--   PART B (UPDATE)       -> commented out. Uncomment ONLY after approving A.
--
-- Apomorphine: intentionally NOT in either list. Per decision, it stays
-- controlled=true (clinical caution) but receives no narcotic/psychotropic
-- class, so it is gated at checkout yet never appears on either EFDA register.
-- ---------------------------------------------------------------------------


-- ===========================================================================
-- PART A  —  PREVIEW (read-only). Run this alone first and review the output.
-- ===========================================================================

WITH efda(pattern, klass) AS (VALUES
    -- ---- NARCOTIC (1961 Convention, Schedules I & II) ----
    ('%codeine%',              'narcotic'),
    ('%cocaine%',              'narcotic'),
    ('%diphenoxylate%',        'narcotic'),
    ('%fentanyl%',             'narcotic'),
    ('%methadone%',            'narcotic'),
    ('%morphine%',             'narcotic'),
    ('%pethidine%',            'narcotic'),
    -- ---- PSYCHOTROPIC (1971 Convention, Schedules III & IV) ----
    ('%alprazolam%',           'psychotropic'),
    ('%bromazepam%',           'psychotropic'),
    ('%chlordiazepoxide%',     'psychotropic'),
    ('%clonazepam%',           'psychotropic'),
    ('%diazepam%',             'psychotropic'),
    ('%dextroamphetamine%',    'psychotropic'),
    ('%flurazepam%',           'psychotropic'),
    ('%lorazepam%',            'psychotropic'),
    ('%medazepam%',            'psychotropic'),
    ('%methylphenidate%',      'psychotropic'),
    ('%midazolam%',            'psychotropic'),
    ('%oxazepam%',             'psychotropic'),
    ('%pentazocine%',          'psychotropic'),
    ('%pentobarbit%',          'psychotropic'),
    ('%phenobarbit%',          'psychotropic'),
    ('%temazepam%',            'psychotropic'),
    ('%zolpidem%',             'psychotropic')
),
matched AS (
    SELECT ds.id          AS sku_id,
           d.inn_name,
           ds.controlled_substance        AS current_controlled,
           ds.narcotic_class              AS current_class,
           e.klass                        AS new_class
    FROM drug d
    JOIN drug_sku ds ON ds.drug_id = d.id
    JOIN efda e ON d.inn_name ILIKE e.pattern
    -- Guard 1: plain Amitriptyline is NOT controlled; only the
    -- Amitriptyline + Chlordiazepoxide combination is (caught by chlordiazepoxide).
    WHERE NOT (d.inn_name ILIKE '%amitriptyline%' AND d.inn_name NOT ILIKE '%chlordiazepoxide%')
    -- Guard 2: 'apomorphine' falsely matches '%morphine%'. It is NOT on the EFDA
    -- list; by decision it stays controlled but unclassified, so exclude it here.
      AND NOT (d.inn_name ILIKE '%apomorphine%')
)
SELECT inn_name,
       count(*)                                   AS skus_affected,
       new_class,
       bool_or(current_controlled)                AS any_already_controlled,
       bool_and(current_controlled)               AS all_already_controlled,
       count(*) FILTER (WHERE current_controlled IS FALSE) AS skus_flag_will_flip_to_true,
       count(*) FILTER (WHERE current_class IS DISTINCT FROM new_class) AS skus_class_will_change
FROM matched
GROUP BY inn_name, new_class
ORDER BY new_class, inn_name;

-- Sanity counts for the preview:
WITH efda(pattern, klass) AS (VALUES
    ('%codeine%','narcotic'),('%cocaine%','narcotic'),('%diphenoxylate%','narcotic'),
    ('%fentanyl%','narcotic'),('%methadone%','narcotic'),('%morphine%','narcotic'),
    ('%pethidine%','narcotic'),
    ('%alprazolam%','psychotropic'),('%bromazepam%','psychotropic'),
    ('%chlordiazepoxide%','psychotropic'),('%clonazepam%','psychotropic'),
    ('%diazepam%','psychotropic'),('%dextroamphetamine%','psychotropic'),
    ('%flurazepam%','psychotropic'),('%lorazepam%','psychotropic'),
    ('%medazepam%','psychotropic'),('%methylphenidate%','psychotropic'),
    ('%midazolam%','psychotropic'),('%oxazepam%','psychotropic'),
    ('%pentazocine%','psychotropic'),('%pentobarbit%','psychotropic'),
    ('%phenobarbit%','psychotropic'),('%temazepam%','psychotropic'),
    ('%zolpidem%','psychotropic')
)
SELECT e.klass,
       count(DISTINCT d.id)  AS distinct_drugs,
       count(ds.id)          AS total_skus
FROM drug d
JOIN drug_sku ds ON ds.drug_id = d.id
JOIN efda e ON d.inn_name ILIKE e.pattern
WHERE NOT (d.inn_name ILIKE '%amitriptyline%' AND d.inn_name NOT ILIKE '%chlordiazepoxide%')
  AND NOT (d.inn_name ILIKE '%apomorphine%')
GROUP BY e.klass
ORDER BY e.klass;


-- ===========================================================================
-- PART B  —  APPLY (writes). Uncomment the block below ONLY after the preview
--           above looks correct. Runs in a single transaction.
-- ===========================================================================

-- BEGIN;
--
-- WITH efda(pattern, klass) AS (VALUES
--     ('%codeine%','narcotic'),('%cocaine%','narcotic'),('%diphenoxylate%','narcotic'),
--     ('%fentanyl%','narcotic'),('%methadone%','narcotic'),('%morphine%','narcotic'),
--     ('%pethidine%','narcotic'),
--     ('%alprazolam%','psychotropic'),('%bromazepam%','psychotropic'),
--     ('%chlordiazepoxide%','psychotropic'),('%clonazepam%','psychotropic'),
--     ('%diazepam%','psychotropic'),('%dextroamphetamine%','psychotropic'),
--     ('%flurazepam%','psychotropic'),('%lorazepam%','psychotropic'),
--     ('%medazepam%','psychotropic'),('%methylphenidate%','psychotropic'),
--     ('%midazolam%','psychotropic'),('%oxazepam%','psychotropic'),
--     ('%pentazocine%','psychotropic'),('%pentobarbit%','psychotropic'),
--     ('%phenobarbit%','psychotropic'),('%temazepam%','psychotropic'),
--     ('%zolpidem%','psychotropic')
-- ),
-- targets AS (
--     SELECT ds.id AS sku_id, e.klass
--     FROM drug d
--     JOIN drug_sku ds ON ds.drug_id = d.id
--     JOIN efda e ON d.inn_name ILIKE e.pattern
--     WHERE NOT (d.inn_name ILIKE '%amitriptyline%' AND d.inn_name NOT ILIKE '%chlordiazepoxide%')
--       AND NOT (d.inn_name ILIKE '%apomorphine%')
-- )
-- UPDATE drug_sku ds
-- SET narcotic_class      = t.klass,
--     controlled_substance = true
-- FROM targets t
-- WHERE ds.id = t.sku_id;
--
-- -- Verify before committing:
-- SELECT narcotic_class, count(*) AS skus,
--        count(*) FILTER (WHERE controlled_substance) AS controlled
-- FROM drug_sku
-- WHERE narcotic_class IS NOT NULL
-- GROUP BY narcotic_class;
--
-- COMMIT;   -- (or ROLLBACK; if the verify counts look wrong)
