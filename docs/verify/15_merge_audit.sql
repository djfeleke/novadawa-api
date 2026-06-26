-- Lens-2 merge AUDIT (read-only). Resolves names->ids, reports loser dependencies
-- and SKU collisions vs winner. Any NULL loser_id/winner_id = name didn't match (fix).
WITH pairs(lname, wname) AS (VALUES
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
  ('Phenobarbitone (Phenobarbital)','Phenobarbital'),
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
)
SELECT p.wname AS winner,
       dl.id   AS loser_id,
       dw.id   AS winner_id,
       (dl.id IS NULL OR dw.id IS NULL) AS unresolved,
       (SELECT count(*) FROM drug_sku s WHERE s.drug_id=dl.id) AS l_skus,
       (SELECT count(*) FROM drug_sku s WHERE s.drug_id=dl.id
          AND EXISTS (SELECT 1 FROM drug_sku w WHERE w.drug_id=dw.id
              AND w.dosage_form=s.dosage_form AND w.strength IS NOT DISTINCT FROM s.strength)) AS l_skus_collide,
       (SELECT count(*) FROM clinical_reference c WHERE c.drug_id=dl.id) AS l_refs,
       (SELECT count(*) FROM dosing_guideline g WHERE g.drug_id=dl.id) AS l_dosing,
       (SELECT count(*) FROM drug_interaction_cache i WHERE i.drug_a_id=dl.id OR i.drug_b_id=dl.id) AS l_intx,
       (SELECT count(*) FROM product pr JOIN drug_sku s ON pr.drug_sku_id=s.id WHERE s.drug_id=dl.id) AS l_products,
       p.lname AS loser
FROM pairs p
LEFT JOIN drug dl ON dl.inn_name = p.lname
LEFT JOIN drug dw ON dw.inn_name = p.wname
ORDER BY unresolved DESC, l_dosing DESC, l_intx DESC, winner;
