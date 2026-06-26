\echo === Post-commit: empties truly gone (expect 0) ===
SELECT count(*) AS should_be_zero FROM drug WHERE id::text LIKE ANY (ARRAY[
  '7db617fb%','d473f12d%','ca80be93%','080f904e%','1ccef393%','a0c02953%',
  '303f34d8%','ea941fa4%','e113e92b%','d658f266%','2da4815a%','af78d9bd%']);

\echo === Post-commit: Paracetamol owns its 7 SKUs (the original bug) ===
SELECT d.inn_name, count(s.id) AS skus
FROM drug d LEFT JOIN drug_sku s ON s.drug_id=d.id
WHERE d.id::text LIKE 'be7ca43f%' GROUP BY d.inn_name;

\echo === Post-commit: no orphaned FKs anywhere (all expect 0) ===
SELECT 'sku'        AS tbl, count(*) FROM drug_sku               s WHERE NOT EXISTS (SELECT 1 FROM drug d WHERE d.id=s.drug_id)
UNION ALL SELECT 'clinical', count(*) FROM clinical_reference    c WHERE NOT EXISTS (SELECT 1 FROM drug d WHERE d.id=c.drug_id)
UNION ALL SELECT 'dosing',   count(*) FROM dosing_guideline      g WHERE NOT EXISTS (SELECT 1 FROM drug d WHERE d.id=g.drug_id)
UNION ALL SELECT 'intx_a',   count(*) FROM drug_interaction_cache x WHERE NOT EXISTS (SELECT 1 FROM drug d WHERE d.id=x.drug_a_id)
UNION ALL SELECT 'intx_b',   count(*) FROM drug_interaction_cache x WHERE NOT EXISTS (SELECT 1 FROM drug d WHERE d.id=x.drug_b_id);

\echo === Post-commit: total drug count (was ~1391, expect 1391-12 = 1379) ===
SELECT count(*) AS total_drugs FROM drug;
