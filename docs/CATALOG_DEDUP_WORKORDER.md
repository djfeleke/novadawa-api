# Catalog duplicate-drug cleanup - WORK ORDER (investigated 2026-06-23)

## Problem
Duplicate drug rows in the `drug` table. Same drug ingested under 2+ name
variants. Data is SPLIT across the twins: SKUs landed on one row, clinical
monograph + dosing + interactions often on the OTHER. Neither twin is complete.
Surfaced when Products screen showed "No variants found" for Paracetamol -
the row picked had 0 SKUs while its twin had 7.

## Scope (verified, read-only queries only - NO writes done yet)
11 empty rows (0 SKUs) that are content/anagram duplicates of a populated twin.

### Confirmed pairs (empty_id -> populated_id, populated sku_count)
1. Dactinomycin (Actinomycin-D)          7db617fb -> 60d22dea  (1)
2. Daunomycin HCl (Daunorubicin)         d473f12d -> ffe26259  (2)
3. Folinic acid/Leucovorin               ca80be93 -> fd284f83  (2)
4. Hyoscine(Scopolamine) butylbromide    080f904e -> b25860f1  (4)
5. Paracetamol (Acetaminophen)           1ccef393 -> be7ca43f  (7)
6. Phytomenadione (Vitamin K1)           303f34d8 -> f96e2ee2  (3)
7. Sacubitril+Valsartan                  a0c02953 -> 8d7dd1b8  (2)  *typo
8. Terbinafine hydrochloride             ea941fa4 -> f2f4f646  (1)

### Special cases - need individual handling
- EPINEPHRINE: TWO empties -> ONE populated (Adrenaline 8bf88aa9, 5 SKUs)
    e113e92b (Epinephrine (adrenaline))   -> 8bf88aa9
    d658f266 (Epinephrine/adrenaline)     -> 8bf88aa9   (has 18 interactions!)
- SCOPOLAMINE HYDROBROMIDE: THREE-WAY tangle. One empty matches TWO populated
  rows that are themselves duplicates of each other:
    2da4815a (empty) ~ af78d9bd (Hyoscine(Scopolamine) Hydrobromide, 1 SKU)
                     ~ 295627f3 (Hyoscine/Scopolamine Hydrobromide, 2 SKUs)
  => af78d9bd and 295627f3 must ALSO be merged (consolidate 3 SKUs onto one),
     then 2da4815a deleted. Needs its own decision on canonical row.
  NOTE: butylbromide (pair 4) is a DIFFERENT salt - do NOT merge with hydrobromide.

## FK references to `drug` (5 constraints - all must be handled)
  drug_sku.drug_id
  clinical_reference.drug_id        (likely UNIQUE on drug_id - conflict risk)
  drug_interaction_cache.drug_a_id  AND  drug_b_id  (two sides)
  dosing_guideline.drug_id

## What lives where (the split - why naive delete loses data)
- clinical_reference: ALL 11 empties have a monograph. Only 3 populated twins do
  (8bf88aa9, f2f4f646, f96e2ee2). 
    -> 8 pairs: monograph ONLY on empty side - MUST move to canonical or lose it.
    -> 3 pairs: monograph on BOTH - conflict, pick richer one, discard other.
- dosing_guideline: empty Paracetamol 1ccef393 has 2 guidelines (pediatric WHO
  data) - MUST repoint or lose pediatric Paracetamol dosing.
- interactions (drug_a_id): present on nearly all empties; d658f266 has 18.
  7db617fb also on drug_b_id (2). Repoint BOTH sides.

## Migration plan (write next session, fresh - becomes migration 09)
Per canonical row, inside ONE transaction, ROLLBACK-preview first:
  1. Repoint drug_sku.drug_id   empty -> canonical
  2. Resolve clinical_reference: if canonical has none, repoint empty's;
     if both have one, keep canonical's (verify richer), delete empty's.
  3. Repoint dosing_guideline.drug_id  empty -> canonical
  4. Repoint drug_interaction_cache drug_a_id AND drug_b_id empty -> canonical,
     WITH dedup: skip/merge rows that would duplicate an existing pair on the
     canonical row (avoid unique-constraint violation / dupe interactions).
  5. Delete empty drug row.
  6. Handle Epinephrine (2->1) and Scopolamine (3-way) as special blocks.
  7. Fix typo: UPDATE drug SET inn_name='Sacubitril + Valsartan' WHERE id=8d7dd1b8.
  8. Decide canonical NAMING convention (slash form vs parenthetical form?)
     and normalize survivors.

## Wider gap (separate from dedup)
254 of 1391 drugs (18%) have ZERO SKUs. Some are dupes (above), but many are
genuinely un-seeded common drugs (Ampicillin, Aciclovir, Atropine, Albumin,
Benzyl penicillin...). After dedup, recount true gaps -> feeds the SKU-submission
feature (the pending/approval_vote_count community model already in drug_sku
schema). SKU submission needs strength-string normalization (saw irregular
combo strengths like "200mg+28.5mg)/5ml" with stray parens).

## Also parked this session
- Search bug: pg_trgm similarity on inn_name misses the populated twin when the
  common name is buried mid-string (searching "para" did NOT surface
  "Acetaminophen/Paracetamol"). Consider searching brand/synonyms or improving
  ranking so populated rows aren'\''t cut by LIMIT.
- VAT: drug_sku.is_vat_exempt defaults true; Sales checkout applied 15% to a
  drug anyway. Reconcile - checkout should honor SKU is_vat_exempt.
- Dispense relabel -> "Stock adjustment" + reason dropdown (Expired/Damaged/
  Lost/Returned to supplier). Keep transfers/customer-returns out (own paths).
  Reason may need a real column, not just notes, for reporting.
- Receive form -> invoice-native (packs x cost/pack -> derived base qty &
  cost/unit, with reconciliation display). pack_size confirmed as the factor.

## DISCIPLINE
Destructive multi-table migration on FK-referenced CLINICAL data. Do NOT write
or run in a rushed/long session. Read-only verify each step. BEGIN/ROLLBACK
preview before COMMIT. Back up drug + 5 referencing tables first.

## ROOT CAUSE (clarified)
NOT a missing-wiring problem - all 5 tables ARE correctly FK-linked to drug.id.
The cause is DUPLICATE drug rows from data ingestion: the same real drug was
seeded under 2+ name variants (different source naming), and each feature'\''s
data (SKUs vs clinical vs dosing vs interactions) loaded against whichever
name-variant ITS source used. References are all valid - they just point at
two halves of one drug.

PERMANENT FIX = two parts:
1. Clean existing dupes (this work order, migration 09).
2. PREVENT new dupes: ingestion + SKU-submission must normalize drug names and
   dedup-check before INSERT (resolve name variants to one canonical drug).
   This is a design requirement to bake into the SKU-submission feature.
