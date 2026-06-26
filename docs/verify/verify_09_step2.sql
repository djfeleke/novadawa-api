\echo === 2a. clinical_reference conflicts: empty vs canon richness (sum of text fields) ===
SELECT d.id::text AS drug, d.inn_name, c.source,
  coalesce(length(c.indications),0)             AS indic,
  coalesce(length(c.dose_and_administration),0) AS dose,
  coalesce(length(c.contraindications),0)       AS contra,
  coalesce(length(c.drug_interactions_text),0)  AS intx,
  coalesce(length(c.side_effects),0)            AS se,
  coalesce(length(c.cautions),0)                AS caut,
  coalesce(length(c.storage_condition),0)       AS storage,
  ( coalesce(length(c.indications),0)+coalesce(length(c.dose_and_administration),0)
   +coalesce(length(c.contraindications),0)+coalesce(length(c.drug_interactions_text),0)
   +coalesce(length(c.side_effects),0)+coalesce(length(c.cautions),0)
   +coalesce(length(c.storage_condition),0) )   AS total_len
FROM clinical_reference c JOIN drug d ON d.id=c.drug_id
WHERE d.id::text LIKE '8bf88aa9%' OR d.id::text LIKE 'e113e92b%' OR d.id::text LIKE 'd658f266%'
   OR d.id::text LIKE 'f96e2ee2%' OR d.id::text LIKE '303f34d8%'
   OR d.id::text LIKE 'f2f4f646%' OR d.id::text LIKE 'ea941fa4%'
ORDER BY d.inn_name;
