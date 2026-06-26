-- =====================================================================
-- Migration 17: merge 3 far-apart dup clusters (by id).
--   Budesonide +Formoterol Fumarate 602a -> Budesonide + Formoterol      24da
--   Iodine+KI long (Lugol's)        5a2c -> Lugol's solution (...)        0f55
--   contains essential phospholipids 29d2 -> Essential phospholipids      5f40  (junk, 0 children)
-- LEFT ALONE: Soya-based non-milk preparations 8414 (distinct nutritional product).
-- Same child de-collision as migrations 15/16.
-- =====================================================================
BEGIN;

CREATE TEMP TABLE _m ON COMMIT DROP AS
SELECT loser, winner FROM (VALUES
  ('602a4b71-0232-4392-8cd1-ac0f7c79bf2a'::uuid,'24da4b40-2dbe-486a-85f5-8da37f7ef54d'::uuid),
  ('5a2c7587-5460-4d1f-af15-a1fee08f3186','0f55fe8c-74ec-4cef-846d-13ffe3be1885'),
  ('29d24078-31d4-444e-9540-497705548252','5f4055b7-7f2e-4f26-a898-706ecfb22abf')
) v(loser,winner);

SELECT count(*) AS pairs, count(*) FILTER (WHERE loser=winner) AS self_pairs FROM _m;

-- 1. interactions de-collision
DELETE FROM drug_interaction_cache i USING _m m
WHERE (i.drug_a_id=m.loser OR i.drug_b_id=m.loser)
  AND ( m.winner IN (i.drug_a_id,i.drug_b_id)
     OR EXISTS (SELECT 1 FROM drug_interaction_cache w
                WHERE (w.drug_a_id,w.drug_b_id) IN (
                  (m.winner, CASE WHEN i.drug_a_id=m.loser THEN i.drug_b_id ELSE i.drug_a_id END),
                  (CASE WHEN i.drug_a_id=m.loser THEN i.drug_b_id ELSE i.drug_a_id END, m.winner))));
UPDATE drug_interaction_cache i SET drug_a_id=m.winner FROM _m m WHERE i.drug_a_id=m.loser;
UPDATE drug_interaction_cache i SET drug_b_id=m.winner FROM _m m WHERE i.drug_b_id=m.loser;
UPDATE drug_interaction_cache i SET drug_a_name=d.inn_name FROM drug d WHERE d.id=i.drug_a_id;
UPDATE drug_interaction_cache i SET drug_b_name=d.inn_name FROM drug d WHERE d.id=i.drug_b_id;

-- 2. dosing straight repoint
UPDATE dosing_guideline g SET drug_id=m.winner FROM _m m WHERE g.drug_id=m.loser;

-- 3. clinical_reference UNIQUE(drug_id) de-collision
DELETE FROM clinical_reference c USING _m m
WHERE c.drug_id=m.loser AND EXISTS (SELECT 1 FROM clinical_reference w WHERE w.drug_id=m.winner);
UPDATE clinical_reference c SET drug_id=m.winner FROM _m m WHERE c.drug_id=m.loser;

-- 4. drug_sku collision-safe repoint
DELETE FROM drug_sku s USING _m m
WHERE s.drug_id=m.loser
  AND EXISTS (SELECT 1 FROM drug_sku w WHERE w.drug_id=m.winner
              AND w.dosage_form=s.dosage_form AND w.strength IS NOT DISTINCT FROM s.strength);
DELETE FROM drug_sku s USING (
  SELECT s.id, row_number() OVER (PARTITION BY m.winner, s.dosage_form, s.strength ORDER BY s.id) rn
  FROM drug_sku s JOIN _m m ON s.drug_id=m.loser) d
WHERE s.id=d.id AND d.rn>1;
UPDATE drug_sku s SET drug_id=m.winner FROM _m m WHERE s.drug_id=m.loser;

-- 5. delete loser drug rows
DELETE FROM drug d USING _m m WHERE d.id=m.loser;

-- verification
SELECT 'loser_rows_left' AS check, count(*) n FROM drug WHERE id IN
  ('602a4b71-0232-4392-8cd1-ac0f7c79bf2a','5a2c7587-5460-4d1f-af15-a1fee08f3186','29d24078-31d4-444e-9540-497705548252')
UNION ALL SELECT 'self_interactions', count(*) FROM drug_interaction_cache WHERE drug_a_id=drug_b_id
UNION ALL SELECT 'drug_count', count(*) FROM drug
UNION ALL SELECT 'sku_count', count(*) FROM drug_sku;

COMMIT;

