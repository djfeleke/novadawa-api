\pset format wrapped
\echo ================================================================
\echo == The 227: zero-SKU AND not community-approved. Break down by category ==
\echo ================================================================
SELECT coalesce(d.therapeutic_category,'(none)') AS category, count(*) AS n
FROM drug d
WHERE NOT EXISTS (SELECT 1 FROM drug_sku s WHERE s.drug_id=d.id)
  AND d.is_community_pharmacy_approved = false
GROUP BY d.therapeutic_category
ORDER BY n DESC;

\echo ================================================================
\echo == Same 227 by prescription/controlled flags (are these truly specialist?) ==
\echo ================================================================
SELECT
  d.prescription_required, d.controlled_substance,
  count(*) AS n
FROM drug d
WHERE NOT EXISTS (SELECT 1 FROM drug_sku s WHERE s.drug_id=d.id)
  AND d.is_community_pharmacy_approved = false
GROUP BY d.prescription_required, d.controlled_substance
ORDER BY n DESC;

\echo ================================================================
\echo == Junk/non-drug sniff test within the 227 ==
\echo == (device/supply words, description-like names, footnote *, very short or very long) ==
\echo ================================================================
SELECT substr(d.id::text,1,8) AS id, d.inn_name, d.therapeutic_category,
  CASE
    WHEN d.inn_name ~* '(valve|sponge|cellulose|catheter|tube|dressing|gauze|suture|implant|stent|kit|set|bag|device|strip|lancet|syringe|needle|gloves?)' THEN 'DEVICE/SUPPLY'
    WHEN d.inn_name ~ '\*'                                THEN 'FOOTNOTE_*'
    WHEN d.inn_name ~* '^(contains|various|assorted|other|misc|cytotoxic medicines|multivitamin)' THEN 'DESCRIPTION/CATEGORY'
    WHEN length(d.inn_name) < 5                           THEN 'TOO_SHORT'
    WHEN length(d.inn_name) > 70                          THEN 'VERY_LONG'
    ELSE 'looks_like_drug'
  END AS flag
FROM drug d
WHERE NOT EXISTS (SELECT 1 FROM drug_sku s WHERE s.drug_id=d.id)
  AND d.is_community_pharmacy_approved = false
ORDER BY flag, d.inn_name;

\echo ================================================================
\echo == Summary count per flag ==
\echo ================================================================
SELECT flag, count(*) AS n FROM (
  SELECT
    CASE
      WHEN d.inn_name ~* '(valve|sponge|cellulose|catheter|tube|dressing|gauze|suture|implant|stent|kit|set|bag|device|strip|lancet|syringe|needle|gloves?)' THEN 'DEVICE/SUPPLY'
      WHEN d.inn_name ~ '\*'                                THEN 'FOOTNOTE_*'
      WHEN d.inn_name ~* '^(contains|various|assorted|other|misc|cytotoxic medicines|multivitamin)' THEN 'DESCRIPTION/CATEGORY'
      WHEN length(d.inn_name) < 5                           THEN 'TOO_SHORT'
      WHEN length(d.inn_name) > 70                          THEN 'VERY_LONG'
      ELSE 'looks_like_drug'
    END AS flag
  FROM drug d
  WHERE NOT EXISTS (SELECT 1 FROM drug_sku s WHERE s.drug_id=d.id)
    AND d.is_community_pharmacy_approved = false
) t
GROUP BY flag ORDER BY n DESC;
