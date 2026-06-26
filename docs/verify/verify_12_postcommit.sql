\echo === Husks truly gone (expect 0) ===
SELECT count(*) AS husks_remaining FROM drug
WHERE id::text LIKE ANY (ARRAY['0c3285b8%','3721c9af%','5eb396f4%','49c71ba5%','8c280470%','b09eca75%','ae368c11%']);

\echo === No fused names with the N. artifact remain (expect 0) ===
SELECT count(*) AS fused_names_left FROM drug WHERE inn_name ~ '[0-9]{2}\.';

\echo === Real standalone oncology rows intact ===
SELECT substr(id::text,1,8) AS id, inn_name,
  (SELECT count(*) FROM drug_sku s WHERE s.drug_id=d.id) AS skus
FROM drug d WHERE id::text LIKE ANY (ARRAY[
  '7c9db6d0%','a22b1518%','8ab81755%','b97b263c%','6e9f5f22%','4fcfa51b%','1a6d4865%','0941b6dc%'])
ORDER BY inn_name;

\echo === No orphaned SKUs / total counts ===
SELECT (SELECT count(*) FROM drug_sku s WHERE NOT EXISTS (SELECT 1 FROM drug d WHERE d.id=s.drug_id)) AS orphan_skus,
       (SELECT count(*) FROM drug)     AS total_drugs,
       (SELECT count(*) FROM drug_sku) AS total_skus;
