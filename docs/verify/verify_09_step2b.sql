\pset format wrapped
\x on
\echo === EPINEPHRINE: canon 8bf88aa9 vs empty1 e113e92b vs empty2 d658f266 ===
SELECT substr(d.id::text,1,8) AS id, d.inn_name,
  c.indications, c.dose_and_administration, c.contraindications,
  c.drug_interactions_text, c.side_effects, c.cautions, c.storage_condition
FROM clinical_reference c JOIN drug d ON d.id=c.drug_id
WHERE d.id::text LIKE '8bf88aa9%' OR d.id::text LIKE 'e113e92b%' OR d.id::text LIKE 'd658f266%';

\echo === PHYTOMENADIONE: canon f96e2ee2 vs empty 303f34d8 ===
SELECT substr(d.id::text,1,8) AS id, d.inn_name,
  c.indications, c.dose_and_administration, c.contraindications,
  c.drug_interactions_text, c.side_effects, c.cautions, c.storage_condition
FROM clinical_reference c JOIN drug d ON d.id=c.drug_id
WHERE d.id::text LIKE 'f96e2ee2%' OR d.id::text LIKE '303f34d8%';

\echo === TERBINAFINE: canon f2f4f646 vs empty ea941fa4 ===
SELECT substr(d.id::text,1,8) AS id, d.inn_name,
  c.indications, c.dose_and_administration, c.contraindications,
  c.drug_interactions_text, c.side_effects, c.cautions, c.storage_condition
FROM clinical_reference c JOIN drug d ON d.id=c.drug_id
WHERE d.id::text LIKE 'f2f4f646%' OR d.id::text LIKE 'ea941fa4%';
