\pset format wrapped
\echo ================================================================
\echo == HEADLINE: how many drugs have zero SKUs now (was 254/1391) ==
\echo ================================================================
SELECT
  count(*)                                              AS total_drugs,
  count(*) FILTER (WHERE sku_count = 0)                 AS zero_sku,
  round(100.0*count(*) FILTER (WHERE sku_count=0)/count(*),1) AS pct_zero,
  count(*) FILTER (WHERE sku_count > 0)                 AS has_sku
FROM (
  SELECT d.id, (SELECT count(*) FROM drug_sku s WHERE s.drug_id=d.id) AS sku_count
  FROM drug d
) t;

\echo ================================================================
\echo == Are the gaps common retail drugs or niche? Slice by EEML flag ==
\echo == (is_on_eeml = on Ethiopia Essential Medicines List) ==========
\echo ================================================================
SELECT
  d.is_on_eeml,
  count(*) AS drugs,
  count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM drug_sku s WHERE s.drug_id=d.id)) AS zero_sku
FROM drug d
GROUP BY d.is_on_eeml
ORDER BY d.is_on_eeml DESC;

\echo ================================================================
\echo == Slice by community-pharmacy approval (retail relevance) ======
\echo ================================================================
SELECT
  d.is_community_pharmacy_approved,
  count(*) AS drugs,
  count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM drug_sku s WHERE s.drug_id=d.id)) AS zero_sku
FROM drug d
GROUP BY d.is_community_pharmacy_approved
ORDER BY d.is_community_pharmacy_approved DESC;

\echo ================================================================
\echo == The HIGH-PRIORITY gap list: zero-SKU drugs that ARE on EEML ==
\echo == AND community-approved (these are the ones that hurt) ========
\echo ================================================================
SELECT substr(d.id::text,1,8) AS id, d.inn_name, d.therapeutic_category
FROM drug d
WHERE NOT EXISTS (SELECT 1 FROM drug_sku s WHERE s.drug_id=d.id)
  AND d.is_on_eeml = true
  AND d.is_community_pharmacy_approved = true
ORDER BY d.inn_name
LIMIT 60;

\echo ================================================================
\echo == Count of that high-priority bucket =========================
\echo ================================================================
SELECT count(*) AS high_priority_gaps
FROM drug d
WHERE NOT EXISTS (SELECT 1 FROM drug_sku s WHERE s.drug_id=d.id)
  AND d.is_on_eeml = true
  AND d.is_community_pharmacy_approved = true;
