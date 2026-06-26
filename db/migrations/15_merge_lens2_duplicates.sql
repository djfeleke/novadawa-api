-- =====================================================================
-- Migration 15: merge 24 duplicate drug clusters (Lens-2: spelling/OCR/synonym/word-order)
-- Winner = canonical (correct spelling / fuller / clinically-loaded).
-- Child de-collision per audited constraints:
--   drug_interaction_cache: UNIQUE(drug_a_id,drug_b_id) + CHECK(a<>b) -> drop self & dup pairs first
--   dosing_guideline:       no drug_id uniqueness -> straight repoint
--   clinical_reference:     straight repoint
--   drug_sku:               UNIQUE(drug_id,dosage_form,strength) NULLS NOT DISTINCT -> drop colliding, repoint rest
-- =====================================================================
BEGIN;

-- ---------------------------------------------------------------------
-- Phenobarbitone (Phenobarbital)  8189a65c-...  -> HARD DELETE per Dejenu,
-- BUT its 2 dosing guidelines are repointed to the winner first (kept).
-- Its 5 dup SKUs + 9 interactions cascade away.
-- ---------------------------------------------------------------------
SELECT 'loser_skus_lost'        AS item, count(*) FROM drug_sku WHERE drug_id='8189a65c-0d5d-4eaf-8a67-4223c2c945b7'
UNION ALL SELECT 'loser_dosing_lost',  count(*) FROM dosing_guideline WHERE drug_id='8189a65c-0d5d-4eaf-8a67-4223c2c945b7'
UNION ALL SELECT 'loser_intx_lost',    count(*) FROM drug_interaction_cache WHERE drug_a_id='8189a65c-0d5d-4eaf-8a67-4223c2c945b7' OR drug_b_id='8189a65c-0d5d-4eaf-8a67-4223c2c945b7'
UNION ALL SELECT 'winner_dosing_kept', count(*) FROM dosing_guideline WHERE drug_id='aca960dc-9d56-4eb0-8924-fd573adfa9d4'
UNION ALL SELECT 'winner_skus_kept',   count(*) FROM drug_sku WHERE drug_id='aca960dc-9d56-4eb0-8924-fd573adfa9d4';

DELETE FROM drug_interaction_cache WHERE drug_a_id='8189a65c-0d5d-4eaf-8a67-4223c2c945b7' OR drug_b_id='8189a65c-0d5d-4eaf-8a67-4223c2c945b7';
-- preserve the 2 dosing guidelines: repoint to winner (Phenobarbital) BEFORE deleting loser
UPDATE dosing_guideline SET drug_id='aca960dc-9d56-4eb0-8924-fd573adfa9d4'
  WHERE drug_id='8189a65c-0d5d-4eaf-8a67-4223c2c945b7';
DELETE FROM drug WHERE id = '8189a65c-0d5d-4eaf-8a67-4223c2c945b7';  -- cascades remaining SKUs (dup) 

CREATE TEMP TABLE _m ON COMMIT DROP AS
SELECT dl.id AS loser, dw.id AS winner
FROM (VALUES
  ('Granisetrone Hydrochloride','Granisetron Hydrochloride'),
  ('Ondansetrone','Ondansetron'),
  ('Beclomethasone Dipropinate','Beclomethasone Dipropionate'),
  ('Chlorpheniramine malate','Chlorpheniramine Maleate'),
  ('Sodium Chromoglycate','Sodium Cromoglycate'),
  ('Zolendronic acid','Zoledronic acid'),
  ('Aluminium hydroxide + Magnesium trisilicate','Aluminum Hydroxide + Magnesium Trisilicate'),
  ('Calcium Folinate /leucovorin','Calcium Folinate (Leucovorin Calcium)'),
  ('Omega-3-fatty acid','Omega-3-fatty acids'),
  ('Acetylcysteine/N-acetylcysteine','Acetylcysteine'),
  ('Cyclosporine A','Cyclosporine'),
  ('D-Penicillamine/ Penicillamine','Penicillamine'),
  ('Cefalexin/cephalexin','Cephalexin'),
  ('Ethyl Alcohol/ethanol','Ethyl alcohol'),
  ('Sodium valproate and Valproic acid','Valproic acid (sodium valproate)'),
  ('Human Anti rabies Immunoglobulin','Anti-rabies immunoglobulin'),
  ('Orphenadrine Citrate + Paracetamol','Acetaminophen/Paracetamol + Orphenadrine Citrate'),
  ('Acetaminophen + Acetylsalicylic Acid +Caffeine','Acetaminophen/Paracetamol + Acetylsalicylic acid + Caffeine'),
  ('Ne omycin Sulphate + Hydrocortisone + Polymixin B Sulphate','Neomycin + Hydrocortisone + Polymyxin B Sulphate'),
  ('Ox ytetracycline Hydrochloride Hydrocortisone Acetate + Polymyxin B Sulphate','Oxytetracycline Hydrochloride + Hydrocortisone Acetate + Polymixin B sulphate'),
  ('Oxytetracycline Hydrochloride+ Hydrocortisone Acetate + Polymyxin Sulphate','Oxytetracycline Hydrochloride + Hydrocortisone Acetate + Polymixin B sulphate'),
  ('Betamethasone Valerate + Phenylepherine HCl+ Lidocaine HCl','Betamethasone valerate + Phenylephrine Hydrochloride + Lidocaine Hydrochloride'),
  ('Betamethasone valerate+ Phenylephrine HCl + Lidocaine HCl','Betamethasone valerate + Phenylephrine Hydrochloride + Lidocaine Hydrochloride'),
  ('Acyclovir/acyclovir','Acyclovir (Aciclovir)')
) p(lname,wname)
JOIN drug dl ON dl.inn_name = p.lname
JOIN drug dw ON dw.inn_name = p.wname;

-- guard: every pair must resolve to a distinct loser/winner
SELECT count(*) AS resolved_pairs, count(*) FILTER (WHERE loser = winner) AS self_pairs FROM _m;

-- 1. drug_interaction_cache: drop loser interactions that (a) point at the winner
--    (would become self-rows) or (b) duplicate an existing winner pair, in either direction.
DELETE FROM drug_interaction_cache i USING _m m
WHERE (i.drug_a_id = m.loser OR i.drug_b_id = m.loser)
  AND (
        m.winner IN (i.drug_a_id, i.drug_b_id)                       -- becomes self after repoint
     OR EXISTS (                                                     -- winner already has this pair
          SELECT 1 FROM drug_interaction_cache w
          WHERE (w.drug_a_id, w.drug_b_id) IN (
                  (m.winner, CASE WHEN i.drug_a_id=m.loser THEN i.drug_b_id ELSE i.drug_a_id END),
                  (CASE WHEN i.drug_a_id=m.loser THEN i.drug_b_id ELSE i.drug_a_id END, m.winner)
                ))
      );
-- repoint surviving interactions + refresh denormalized names
UPDATE drug_interaction_cache i SET drug_a_id = m.winner FROM _m m WHERE i.drug_a_id = m.loser;
UPDATE drug_interaction_cache i SET drug_b_id = m.winner FROM _m m WHERE i.drug_b_id = m.loser;
UPDATE drug_interaction_cache i SET drug_a_name = d.inn_name FROM drug d WHERE d.id = i.drug_a_id;
UPDATE drug_interaction_cache i SET drug_b_name = d.inn_name FROM drug d WHERE d.id = i.drug_b_id;

-- 2. dosing_guideline: straight repoint (no drug_id uniqueness)
UPDATE dosing_guideline g SET drug_id = m.winner FROM _m m WHERE g.drug_id = m.loser;

-- 3. clinical_reference: UNIQUE(drug_id) -> drop loser's row if winner already has one, else repoint
DELETE FROM clinical_reference c USING _m m
WHERE c.drug_id = m.loser
  AND EXISTS (SELECT 1 FROM clinical_reference w WHERE w.drug_id = m.winner);
UPDATE clinical_reference c SET drug_id = m.winner FROM _m m WHERE c.drug_id = m.loser;

-- 4. drug_sku: collision-safe repoint. A loser SKU's target slot (winner,form,strength)
--    may already be taken by the winner OR by another loser merging into the same winner.
--    Keep exactly one per slot; delete the rest.
-- 4a. drop loser SKUs whose slot the winner already occupies
DELETE FROM drug_sku s USING _m m
WHERE s.drug_id = m.loser
  AND EXISTS (SELECT 1 FROM drug_sku w WHERE w.drug_id = m.winner
              AND w.dosage_form = s.dosage_form
              AND w.strength IS NOT DISTINCT FROM s.strength);
-- 4b. among loser SKUs targeting the same winner slot, keep one, delete the duplicates
DELETE FROM drug_sku s USING (
  SELECT s.id,
         row_number() OVER (PARTITION BY m.winner, s.dosage_form, s.strength ORDER BY s.id) AS rn
  FROM drug_sku s JOIN _m m ON s.drug_id = m.loser
) d
WHERE s.id = d.id AND d.rn > 1;
-- 4c. repoint the survivors
UPDATE drug_sku s SET drug_id = m.winner FROM _m m WHERE s.drug_id = m.loser;

-- 5. delete the now-emptied loser drug rows
DELETE FROM drug d USING _m m WHERE d.id = m.loser;

-- ---- post-merge verification (all should be clean) ----
SELECT 'remaining_norm_dupes' AS check, count(*) AS n FROM (
  SELECT lower(regexp_replace(inn_name,'[^a-zA-Z0-9]','','g')) k
  FROM drug GROUP BY 1 HAVING count(*)>1) z
UNION ALL
SELECT 'loser_rows_left', count(*) FROM drug d JOIN (VALUES
  ('Granisetrone Hydrochloride','Granisetron Hydrochloride'),
  ('Ondansetrone','Ondansetron'),
  ('Beclomethasone Dipropinate','Beclomethasone Dipropionate'),
  ('Chlorpheniramine malate','Chlorpheniramine Maleate'),
  ('Sodium Chromoglycate','Sodium Cromoglycate'),
  ('Zolendronic acid','Zoledronic acid'),
  ('Aluminium hydroxide + Magnesium trisilicate','Aluminum Hydroxide + Magnesium Trisilicate'),
  ('Calcium Folinate /leucovorin','Calcium Folinate (Leucovorin Calcium)'),
  ('Omega-3-fatty acid','Omega-3-fatty acids'),
  ('Acetylcysteine/N-acetylcysteine','Acetylcysteine'),
  ('Cyclosporine A','Cyclosporine'),
  ('D-Penicillamine/ Penicillamine','Penicillamine'),
  ('Cefalexin/cephalexin','Cephalexin'),
  ('Ethyl Alcohol/ethanol','Ethyl alcohol'),
  ('Sodium valproate and Valproic acid','Valproic acid (sodium valproate)'),
  ('Human Anti rabies Immunoglobulin','Anti-rabies immunoglobulin'),
  ('Orphenadrine Citrate + Paracetamol','Acetaminophen/Paracetamol + Orphenadrine Citrate'),
  ('Acetaminophen + Acetylsalicylic Acid +Caffeine','Acetaminophen/Paracetamol + Acetylsalicylic acid + Caffeine'),
  ('Ne omycin Sulphate + Hydrocortisone + Polymixin B Sulphate','Neomycin + Hydrocortisone + Polymyxin B Sulphate'),
  ('Ox ytetracycline Hydrochloride Hydrocortisone Acetate + Polymyxin B Sulphate','Oxytetracycline Hydrochloride + Hydrocortisone Acetate + Polymixin B sulphate'),
  ('Oxytetracycline Hydrochloride+ Hydrocortisone Acetate + Polymyxin Sulphate','Oxytetracycline Hydrochloride + Hydrocortisone Acetate + Polymixin B sulphate'),
  ('Betamethasone Valerate + Phenylepherine HCl+ Lidocaine HCl','Betamethasone valerate + Phenylephrine Hydrochloride + Lidocaine Hydrochloride'),
  ('Betamethasone valerate+ Phenylephrine HCl + Lidocaine HCl','Betamethasone valerate + Phenylephrine Hydrochloride + Lidocaine Hydrochloride'),
  ('Acyclovir/acyclovir','Acyclovir (Aciclovir)')
) p(lname,wname) ON d.inn_name = p.lname
UNION ALL
SELECT 'self_interactions', count(*) FROM drug_interaction_cache WHERE drug_a_id = drug_b_id
UNION ALL
SELECT 'drug_count', count(*) FROM drug
UNION ALL
SELECT 'sku_count', count(*) FROM drug_sku;

COMMIT;

