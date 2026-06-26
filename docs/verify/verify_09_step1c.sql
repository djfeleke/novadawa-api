\echo === 1c. Where the data lives (per row, current state) ===
WITH ids(label,kind,pfx) AS (VALUES
 ('Dactinomycin','empty','7db617fb'),('Dactinomycin','canon','60d22dea'),
 ('Daunomycin','empty','d473f12d'),('Daunomycin','canon','ffe26259'),
 ('Folinic','empty','ca80be93'),('Folinic','canon','fd284f83'),
 ('Hyoscine-butyl','empty','080f904e'),('Hyoscine-butyl','canon','b25860f1'),
 ('Paracetamol','empty','1ccef393'),('Paracetamol','canon','be7ca43f'),
 ('Phytomenadione','empty','303f34d8'),('Phytomenadione','canon','f96e2ee2'),
 ('Sacubitril+Val','empty','a0c02953'),('Sacubitril+Val','canon','8d7dd1b8'),
 ('Terbinafine','empty','ea941fa4'),('Terbinafine','canon','f2f4f646'),
 ('Epinephrine','empty1','e113e92b'),('Epinephrine','empty2','d658f266'),('Epinephrine','canon','8bf88aa9'),
 ('Scopolamine','empty','2da4815a'),('Scopolamine','canonA','af78d9bd'),('Scopolamine','canonB','295627f3')
), r AS (
  SELECT i.label,i.kind,i.pfx,(SELECT d.id FROM drug d WHERE d.id::text LIKE i.pfx||'%') AS id
  FROM ids i
)
SELECT r.label,r.kind,r.pfx,
  (SELECT count(*) FROM drug_sku s WHERE s.drug_id=r.id)                                AS skus,
  (SELECT count(*) FROM clinical_reference c WHERE c.drug_id=r.id)                      AS clin,
  (SELECT count(*) FROM dosing_guideline g WHERE g.drug_id=r.id)                        AS dosing,
  (SELECT count(*) FROM drug_interaction_cache x WHERE x.drug_a_id=r.id)                AS int_a,
  (SELECT count(*) FROM drug_interaction_cache x WHERE x.drug_b_id=r.id)                AS int_b
FROM r ORDER BY r.label, r.kind;
