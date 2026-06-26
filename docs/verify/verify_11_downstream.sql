\echo === FK references TO drug_sku (find product/inventory columns) ===
SELECT tc.table_name, kcu.column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu USING (constraint_name)
JOIN information_schema.constraint_column_usage ccu USING (constraint_name)
WHERE tc.constraint_type='FOREIGN KEY' AND ccu.table_name='drug_sku'
ORDER BY tc.table_name;

\echo === Do any SKUs on the fused/junk rows have downstream product rows? ===
SELECT substr(d.id::text,1,8) AS drug, d.inn_name, count(p.*) AS products
FROM drug d
JOIN drug_sku s ON s.drug_id=d.id
LEFT JOIN product p ON p.drug_sku_id=s.id
WHERE d.id::text LIKE ANY (ARRAY[
  '0c3285b8%','3721c9af%','5eb396f4%','49c71ba5%','8c280470%','b09eca75%',
  'ae368c11%','28856e04%','b96da4ef%','7c8cca4b%'])
GROUP BY d.id, d.inn_name
ORDER BY products DESC, d.inn_name;
