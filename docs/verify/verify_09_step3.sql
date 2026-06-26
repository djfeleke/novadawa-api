\echo === Schema: drug_interaction_cache (looking for unique on a_id,b_id) ===
\d drug_interaction_cache

\echo === Schema: dosing_guideline ===
\d dosing_guideline

\echo === Scopolamine 3-way detail (pick survivor) ===
SELECT substr(d.id::text,1,8) AS id, d.inn_name,
  (SELECT count(*) FROM drug_sku s WHERE s.drug_id=d.id)               AS skus,
  (SELECT count(*) FROM clinical_reference c WHERE c.drug_id=d.id)     AS clin,
  (SELECT count(*) FROM drug_interaction_cache x
     WHERE x.drug_a_id=d.id OR x.drug_b_id=d.id)                       AS inter,
  d.atc_code, d.is_on_eeml, d.prescription_required, d.controlled_substance, d.created_at
FROM drug d
WHERE d.id::text LIKE '2da4815a%' OR d.id::text LIKE 'af78d9bd%' OR d.id::text LIKE '295627f3%'
ORDER BY skus DESC;

\echo === Do any interactions exist BETWEEN the empties and their canon? (self-loop risk preview) ===
SELECT substr(drug_a_id::text,1,8) AS a, substr(drug_b_id::text,1,8) AS b
FROM drug_interaction_cache
WHERE (drug_a_id::text LIKE '1ccef393%' AND drug_b_id::text LIKE 'be7ca43f%')  -- Paracetamol empty<->canon
   OR (drug_a_id::text LIKE 'be7ca43f%' AND drug_b_id::text LIKE '1ccef393%')
   OR (drug_a_id::text LIKE 'd658f266%' AND drug_b_id::text LIKE '8bf88aa9%')  -- Epi empty2<->canon
   OR (drug_a_id::text LIKE '8bf88aa9%' AND drug_b_id::text LIKE 'd658f266%')
   OR (drug_a_id::text LIKE 'e113e92b%' AND drug_b_id::text LIKE '8bf88aa9%')  -- Epi empty1<->canon
   OR (drug_a_id::text LIKE '8bf88aa9%' AND drug_b_id::text LIKE 'e113e92b%');
