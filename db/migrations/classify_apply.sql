-- classify_apply.sql  (apply step; runs in one transaction, auto-commits only if counts match)
BEGIN;

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
),
targets AS (
    SELECT ds.id AS sku_id, e.klass
    FROM drug d
    JOIN drug_sku ds ON ds.drug_id = d.id
    JOIN efda e ON d.inn_name ILIKE e.pattern
    WHERE NOT (d.inn_name ILIKE '%amitriptyline%' AND d.inn_name NOT ILIKE '%chlordiazepoxide%')
      AND NOT (d.inn_name ILIKE '%apomorphine%')
)
UPDATE drug_sku ds
SET narcotic_class       = t.klass,
    controlled_substance = true
FROM targets t
WHERE ds.id = t.sku_id;

SELECT narcotic_class,
       count(*) AS skus,
       count(*) FILTER (WHERE controlled_substance) AS controlled
FROM drug_sku
WHERE narcotic_class IS NOT NULL
GROUP BY narcotic_class
ORDER BY narcotic_class;

SELECT
    (SELECT count(*) FROM drug_sku WHERE narcotic_class='narcotic') = 26
AND (SELECT count(*) FROM drug_sku WHERE narcotic_class='narcotic' AND controlled_substance) = 26
AND (SELECT count(*) FROM drug_sku WHERE narcotic_class='psychotropic') = 38
AND (SELECT count(*) FROM drug_sku WHERE narcotic_class='psychotropic' AND controlled_substance) = 38
    AS counts_ok \gset

\if :counts_ok
    \echo '>>> Verify counts OK (26/26, 38/38). Committing.'
    COMMIT;
\else
    \echo '>>> Verify counts MISMATCH. Rolling back - nothing changed.'
    ROLLBACK;
\endif
