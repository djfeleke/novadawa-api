BEGIN;
UPDATE drug_sku ds
SET narcotic_class = 'narcotic'
FROM drug d
WHERE ds.drug_id = d.id
  AND d.inn_name ILIKE '%tramadol%'
  AND ds.controlled_substance
  AND ds.narcotic_class IS NULL;

SELECT d.inn_name, ds.narcotic_class, count(*) AS skus
FROM drug d JOIN drug_sku ds ON ds.drug_id=d.id
WHERE d.inn_name ILIKE '%tramadol%'
GROUP BY d.inn_name, ds.narcotic_class;

SELECT count(*) AS remaining_unclassified_controlled
FROM drug_sku WHERE controlled_substance AND narcotic_class IS NULL;
COMMIT;
