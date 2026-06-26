\echo === drug_sku full schema (get real column names) ===
\d drug_sku

\echo === ALL SKUs on the 7 fusion husks, full detail, grouped by husk ===
SELECT
  substr(d.id::text,1,8)  AS husk,
  d.inn_name              AS husk_name,
  substr(s.id::text,1,8)  AS sku,
  s.*
FROM drug d
JOIN drug_sku s ON s.drug_id = d.id
WHERE d.id::text LIKE ANY (ARRAY[
  '0c3285b8%','3721c9af%','5eb396f4%','49c71ba5%','8c280470%','b09eca75%','ae368c11%'])
ORDER BY d.inn_name, s.strength;
