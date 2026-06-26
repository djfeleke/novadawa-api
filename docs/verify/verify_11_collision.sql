\echo === What does bceeac1b match now? ===
SELECT id::text AS full_id, inn_name, created_at
FROM drug WHERE id::text LIKE 'bceeac1b%'
ORDER BY created_at;

\echo === Sanity: did the 3 Tier-1 rename rows survive as unique too? ===
SELECT id::text, inn_name FROM drug
WHERE id::text LIKE '28856e04%' OR id::text LIKE 'b96da4ef%' OR id::text LIKE '7c8cca4b%'
ORDER BY inn_name;

\echo === Current total drug count (was 1379 after migration 09) ===
SELECT count(*) AS total_drugs FROM drug;
