\pset format wrapped
\echo === A. The infinity-symbol rows (junk char U+221E) ===
SELECT substr(id::text,1,8) AS id, inn_name,
  (SELECT count(*) FROM drug_sku s WHERE s.drug_id=d.id) AS skus
FROM drug d WHERE inn_name LIKE '%' || chr(8734) || '%';

\echo === B. Import-artifact patterns (stray dots, digits-in-name, double spaces) ===
SELECT substr(id::text,1,8) AS id, inn_name,
  (SELECT count(*) FROM drug_sku s WHERE s.drug_id=d.id) AS skus
FROM drug d
WHERE inn_name ~ '\.\.'          -- ".." like the 10.. artifact
   OR inn_name ~ '\)\s*\w.*\('   -- ")word...(" -> two parenthetical names fused
   OR inn_name ~ '\s{2,}'        -- double+ spaces
   OR inn_name ~ '[0-9]{2,}'     -- 2+ consecutive digits mid-name (often artifact)
ORDER BY inn_name;

\echo === C. Names containing two drug-like halves (multiple capitalized words after a close-paren) ===
SELECT substr(id::text,1,8) AS id, inn_name
FROM drug d
WHERE inn_name ~ '\)\s+[A-Z][a-z]+'   -- ") Capitalword" mid-string
ORDER BY inn_name;

\echo === D. Suspiciously long names (top 15 by length - fusions tend to be long) ===
SELECT substr(id::text,1,8) AS id, length(inn_name) AS len, inn_name
FROM drug ORDER BY length(inn_name) DESC LIMIT 15;

\echo === E. Leading/trailing whitespace or stray leading/trailing punctuation ===
SELECT substr(id::text,1,8) AS id, '['||inn_name||']' AS bracketed
FROM drug
WHERE inn_name <> btrim(inn_name)
   OR inn_name ~ '^[^A-Za-z0-9]'   -- starts with non-alphanumeric
   OR inn_name ~ '[^A-Za-z0-9)]$'  -- ends with odd punctuation (allow close-paren)
ORDER BY inn_name;
