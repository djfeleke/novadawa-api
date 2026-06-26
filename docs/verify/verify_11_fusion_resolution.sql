\pset format wrapped
-- ===========================================================================
-- READ-ONLY. Resolve each fused/junk row: find its "other half", inspect SKUs.
-- ===========================================================================

\echo ================================================================
\echo == CLASS 1: numbered-list fusions. For each, the row holds the END of
\echo == one drug + START of the next. Find if each half exists separately.
\echo ================================================================

\echo --- 1a. The fused rows themselves + their SKUs (strength/form tells us which half owns them) ---
SELECT substr(d.id::text,1,8) AS id, d.inn_name,
       s.strength, s.dosage_form, s.id::text AS sku_id
FROM drug d JOIN drug_sku s ON s.drug_id = d.id
WHERE d.id::text LIKE ANY (ARRAY[
  '0c3285b8%','3721c9af%','5eb396f4%','49c71ba5%','8c280470%','b09eca75%','ae368c11%'])
ORDER BY d.inn_name, s.strength;

\echo --- 1b. Do the individual drug halves already exist as their own rows? ---
SELECT substr(id::text,1,8) AS id, inn_name,
       (SELECT count(*) FROM drug_sku s WHERE s.drug_id=d.id) AS skus
FROM drug d
WHERE inn_name ILIKE ANY (ARRAY[
  'Carboplatin%','Carmustine%',
  'Etoposide%','Fludarabine%',
  '5-Flu%','Flurouracil%','Fluorouracil%','Gemcitabine%',
  'Vincristine%','Vinorelbine%',
  'Sodium Chloride%'])
  AND inn_name !~ '[0-9]{2}\.'   -- exclude the fused rows themselves
ORDER BY inn_name;

\echo ================================================================
\echo == CLASS 2: infinity-symbol rows
\echo ================================================================
\echo --- 2a. The rows + SKUs ---
SELECT substr(d.id::text,1,8) AS id, d.inn_name,
       s.strength, s.dosage_form
FROM drug d JOIN drug_sku s ON s.drug_id=d.id
WHERE d.id::text LIKE ANY (ARRAY['28856e04%','b96da4ef%','7c8cca4b%'])
ORDER BY d.inn_name;

\echo --- 2b. Do clean versions already exist? (Ferrous salt, Folic acid, Oxymetholone) ---
SELECT substr(id::text,1,8) AS id, inn_name,
       (SELECT count(*) FROM drug_sku s WHERE s.drug_id=d.id) AS skus
FROM drug d
WHERE inn_name ILIKE ANY (ARRAY['Ferrous%','%Folic Acid%','Oxymetholone%'])
ORDER BY inn_name;

\echo ================================================================
\echo == CLASS 3: orphan fragment "Solution) Sodium Citrate..."
\echo ================================================================
\echo --- 3a. The fragment row + SKUs ---
SELECT substr(d.id::text,1,8) AS id, d.inn_name,
       s.strength, s.dosage_form
FROM drug d LEFT JOIN drug_sku s ON s.drug_id=d.id
WHERE d.id::text LIKE 'bceeac1b%';

\echo --- 3b. Candidate "head" rows ending in a Solution-type name (its missing front half) ---
SELECT substr(id::text,1,8) AS id, inn_name
FROM drug
WHERE inn_name ILIKE '%citrate%' OR inn_name ILIKE '%ORS%'
   OR inn_name ILIKE '%oral rehydration%' OR inn_name ILIKE '%dextrose%'
ORDER BY inn_name;

\echo ================================================================
\echo == Also: clinical/dosing/interaction footprint of EVERY fused row
\echo == (a split must carry these too, not just SKUs)
\echo ================================================================
SELECT substr(d.id::text,1,8) AS id, d.inn_name,
  (SELECT count(*) FROM drug_sku s WHERE s.drug_id=d.id)            AS skus,
  (SELECT count(*) FROM clinical_reference c WHERE c.drug_id=d.id)  AS clin,
  (SELECT count(*) FROM dosing_guideline g WHERE g.drug_id=d.id)    AS dosing,
  (SELECT count(*) FROM drug_interaction_cache x
     WHERE x.drug_a_id=d.id OR x.drug_b_id=d.id)                    AS inter
FROM drug d
WHERE d.id::text LIKE ANY (ARRAY[
  '0c3285b8%','3721c9af%','5eb396f4%','49c71ba5%','8c280470%','b09eca75%',
  'ae368c11%','28856e04%','b96da4ef%','7c8cca4b%','bceeac1b%'])
ORDER BY d.inn_name;
