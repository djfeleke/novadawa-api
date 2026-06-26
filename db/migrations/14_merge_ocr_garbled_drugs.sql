-- Migration 14: merge 5 OCR-garbled duplicate drug rows into their canonical spellings.
BEGIN;

UPDATE drug_sku SET drug_id = '2593fbfa-ea0d-4c1e-9dab-f35eb00906c5'
  WHERE id = 'cdde6529-ea46-4577-b132-e6ada8ef9f86';   -- Chloramphenicol Drops 1%
UPDATE drug_sku SET drug_id = '664d34c5-501b-405c-adb1-42e91ca43769'
  WHERE id = '7a7e8e8e-9970-483b-acb4-eb154e5d79ba';   -- Gentamicin Drops 0.3%

DELETE FROM drug_sku WHERE id IN (
  '8618344e-f16a-4980-aa77-e28a39584a1b',
  '506f12c1-9b76-453d-aa6d-fa9868cd63b4',
  '1609c366-2f20-45bb-af80-985d60743b87'
);

DELETE FROM drug WHERE id IN (
  '5784d9c0-7b0b-41b2-8ba3-7ffdd5a5f3be',
  '7185763d-afb0-465e-990e-9392baba77da',
  '27f1c730-c429-426c-8fdb-93d17e394b2d',
  'dde3de05-e992-4f11-aae3-123051a060cc',
  'e02cc68a-2d0e-4904-87af-f22509bcd411'
);

-- verify: should return 5 rows, each count = 1, none with a leading-space variant
SELECT inn_name, count(*) FROM drug
WHERE inn_name IN ('Chloramphenicol','Cocaine Hydrochloride','Gentamicin','Hydrogen Peroxide','Hydroxychloroquine')
   OR inn_name LIKE 'Ch %' OR inn_name LIKE 'Co %' OR inn_name LIKE 'Ge %' OR inn_name LIKE 'Hy %'
GROUP BY inn_name ORDER BY inn_name;

COMMIT;

