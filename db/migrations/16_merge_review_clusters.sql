-- =====================================================================
-- Migration 16: merge 4 review-cluster duplicates (by drug id).
--   Vardenafil T            1ffa974f -> Vardenafil          124fe06b
--   Mitomycin               d47cd499 -> Mitomycin C         ee52ef57
--   Ampicillin Na+Sulb Na   a5230993 -> Ampicillin+sulbactam d06f17d2
--   Aciclovir               facec715 -> Acyclovir (Aciclovir) ee270298
-- Same child de-collision as migration 15.
-- LEFT ALONE: Methylsalicillate pair (distinct), Mechlorethamine (rename, not merge).
-- =====================================================================
BEGIN;

CREATE TEMP TABLE _m ON COMMIT DROP AS
SELECT loser, winner FROM (VALUES
  ('1ffa974f-c3d4-41d0-8b31-69aab184c52d'::uuid,'124fe06b-f0b9-4dea-b1e2-77555dafe3dd'::uuid),
  ('d47cd499-c4c7-4d38-a613-c58940dd1470','ee52ef57-8676-4164-950d-36dea9bc462c'),
  ('a5230993-fef5-48bf-b080-a42d523dad3c','d06f17d2-eaef-4b61-a7fd-a073ab0fbcfa'),
  ('facec715-0ab7-499c-8867-260f932c0058','ee270298-f80a-438c-a039-26206bc9155b')
) v(loser,winner);

SELECT count(*) AS pairs, count(*) FILTER (WHERE loser=winner) AS self_pairs FROM _m;

-- 1. interactions: drop loser rows that would self-pair or duplicate a winner pair (either direction)
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

-- 2. dosing_guideline: straight repoint (no drug_id uniqueness)
UPDATE dosing_guideline g SET drug_id=m.winner FROM _m m WHERE g.drug_id=m.loser;

-- 3. clinical_reference: UNIQUE(drug_id) -> drop loser's if winner has one, else repoint
DELETE FROM clinical_reference c USING _m m
WHERE c.drug_id=m.loser AND EXISTS (SELECT 1 FROM clinical_reference w WHERE w.drug_id=m.winner);
UPDATE clinical_reference c SET drug_id=m.winner FROM _m m WHERE c.drug_id=m.loser;

-- 4. drug_sku: collision-safe repoint
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
  ('1ffa974f-c3d4-41d0-8b31-69aab184c52d','d47cd499-c4c7-4d38-a613-c58940dd1470',
   'a5230993-fef5-48bf-b080-a42d523dad3c','facec715-0ab7-499c-8867-260f932c0058')
UNION ALL SELECT 'self_interactions', count(*) FROM drug_interaction_cache WHERE drug_a_id=drug_b_id
UNION ALL SELECT 'drug_count', count(*) FROM drug
UNION ALL SELECT 'sku_count', count(*) FROM drug_sku;

COMMIT;

