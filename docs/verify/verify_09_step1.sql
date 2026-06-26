\echo === 1a. FK columns referencing drug ===
SELECT tc.table_name, kcu.column_name, tc.constraint_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu USING (constraint_name)
JOIN information_schema.constraint_column_usage ccu USING (constraint_name)
WHERE tc.constraint_type='FOREIGN KEY' AND ccu.table_name='drug'
ORDER BY tc.table_name, kcu.column_name;

\echo === 1b. Confirm each short prefix resolves to exactly ONE drug row ===
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
)
SELECT i.label,i.kind,i.pfx,
  (SELECT count(*) FROM drug d WHERE d.id::text LIKE i.pfx||'%') AS matches,
  (SELECT d.inn_name FROM drug d WHERE d.id::text LIKE i.pfx||'%' LIMIT 1) AS inn_name
FROM ids i ORDER BY i.label,i.kind;
