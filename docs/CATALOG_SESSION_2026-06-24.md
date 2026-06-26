# NovaDawa Catalog Session — Handoff (2026-06-24)

Status at end of session: **3 migrations committed & verified.** Catalog went
**1391 → 1371 drugs**, **2454 → 2164 SKUs**. All removals were hard-evidence
duplicates or synthetic junk — no legitimate catalog data was deleted.

Backups (pg_dump, --column-inserts, restorable) live in
`D:\Desktop\Projects\novadawa-api\backups\`:
- `dedup09_backup_*.sql` — pre-09 (drug + 5 referencing tables)
- `pre_mig12_*.sql` — pre-12 (drug + drug_sku)

---

## DONE THIS SESSION

### Migration 09 — catalog dedup (`migrations/09_catalog_dedup.sql`)
Merged **12 duplicate drug rows** (same real drug seeded under 2+ name variants;
data split across twins). Per pair, in one transaction: repointed `drug_sku`,
`clinical_reference`, `dosing_guideline`, `drug_interaction_cache` (both
drug_a_id AND drug_b_id, with dedup against existing canon pairs in BOTH
orientations to respect the unique `(drug_a_id,drug_b_id)` index + the
`drug_a_id<>drug_b_id` CHECK), then deleted the empty.
- **clinical_reference.drug_id is UNIQUE** — a drug can hold only ONE monograph.
  For the 3 conflict pairs where canon already had a monograph, decided by
  READING the actual text (not length): Epinephrine kept empty2 `d658f266`'s
  richer monograph (deleted canon's first, then repointed); Phytomenadione &
  Terbinafine kept canon's (empty's died via cascade). Terbinafine's empty was
  rejected because it falsely said "No significant drug interactions".
- Epinephrine 3-way (2 empties → canon `8bf88aa9`), Scopolamine 3-way
  (survivor `295627f3`, 2 SKU).
- Fixed Sacubitril typo → "Sacubitril + Valsartan" (`8d7dd1b8`).
- **Fixed the original Paracetamol "No variants found" bug** — canon
  `be7ca43f` now owns all 7 SKUs.
- Result: 1391 → **1379**. Verified: 0 empties remain, 0 orphaned FKs, 0 self-loops.

### Migration 11 — name cleanup (`migrations/11_name_cleanup_tier1_2.sql`)
- Renamed 3 rows to strip junk: `Ferrous Salt∞`→"Ferrous Salt",
  `Ferrous Salt∞ +Folic Acid`→"Ferrous Salt + Folic Acid",
  `Oxymetholone ∞Any ferrous salt…`→"Oxymetholone".
- Deleted 1 empty orphan fragment `bceeac1b` ("Solution) Sodium Citrate…",
  0 of everything).
- Result: 1379 → **1378**. (NOTE: the `∞` was a real junk char U+221E in the
  data; but `ΓÇô`/`┬░C` etc. in the console are just cp437 rendering valid
  UTF-8 — NOT corrupt. Do not "fix" console mojibake.)

### Migration 12 — fusion husks (`migrations/12_drop_fusion_husks.sql`)
Deleted **7 numbered-list fusion rows** + their **27 synthetic SKUs**:
`Carboplatin 11. Carmustine`, `Etoposide 23. Fludarabine`,
`Express Tube 11. 5-Flurouracil`, `Fluorouracil 25. Gemcitabine`,
`Vincristine Sulphate 45. Vinorelbine`, `Sodium Chloride 16. …`,
`Lactated Potassium Saline (Darrow's) 10.. Lactated Ringer's (Hartmann's)`.
- The SKUs were proven **synthetic seed data**, not real product:
  all 27 share ONE microsecond timestamp `2026-06-08 00:34:04.483808+00`,
  all `efda_approved=f`, no manufacturer/reg-number/route, `approval_vote_count=0`,
  implausible form/strength (Vincristine 30mg Capsule, Carboplatin 20mg Ointment).
- Clean standalone rows for each real drug already exist; 0 downstream products.
- Two hard guards in the migration aborted-on-fail (downstream-ref check +
  provenance check). Result: 1378 → **1371** drugs, → **2164** SKUs.

### Migration discipline notes (apply to future ones)
- All 5 FKs to `drug` are **ON DELETE CASCADE** → must repoint BEFORE delete.
- These cleanup migrations are **NOT idempotent** — re-running after COMMIT
  trips the prefix/guard checks (correct behavior, don't re-run).
- Pattern that worked: write SQL to file, run `psql -v ON_ERROR_STOP=1 -f`,
  default to ROLLBACK preview, flip to COMMIT only after preview verified,
  then an INDEPENDENT post-commit verify query (don't trust the migration's
  own output).

---

## THE BIG FINDING — the real SKU gap & its source

Post-cleanup, **242 drugs have zero SKUs**. Sliced by retail relevance:
- **15** are community-approved + zero-SKU → mostly devices / junk / mis-typed.
- **227** are NON-community-approved + zero-SKU → these are **REAL ESSENTIAL
  DRUGS**: Ampicillin, Cloxacillin, Cefazolin; the whole TB line (Isoniazid,
  Rifampicin, Ethambutol, Pyrazinamide + FDCs); the whole HIV/ARV line
  (Dolutegravir, Tenofovir, Lamivudine, Efavirenz…); anaesthetics (Ketamine,
  Halothane, Isoflurane); controlled (Morphine, Methadone, Codeine, Pethidine,
  Buprenorphine, Phenobarbital). The work order predicted exactly this
  ("Ampicillin, Aciclovir, Atropine, Albumin, Benzyl penicillin").

### Source diagnosis (DONE — this is the key result)
Source PDFs live in **`D:\Desktop\EDispensingTool\`** (NOT in the repo):
- **LMCP** = `List-of-Medicines-for-Community-Pharmacy.pdf` (EFDA 5th ed,
  Oct 2021, 139pp, real text layer). Entries are `Drug | Form Strength`
  = exactly SKU data. This is what `is_community_pharmacy_approved` reflects.
- **EML** = `Ethiopian-Essential-Medicines-List-Oct-2024.pdf` (broader; the
  hospital/program scope).
- **EMF** = `Medicine-Formulary-3rd-edition-2025.pdf` = confirmed source of the
  clinical monographs (DB tag `EMF_3rd_Edition_2025`).
- WHO EML xlsx in `~/Downloads`.

**Cross-check verified the gap is MIXED:**
- Ampicillin & Aciclovir **ARE in the LMCP with strengths** but have 0 SKUs in
  DB → **PARSER MISS** (data exists in source, extraction dropped it →
  RECOVERABLE by re-extraction).
- Isoniazid & Rifampicin **are NOT in the LMCP** → correctly zero-SKU for
  community pharmacy (TB program drugs, not retail) → **genuine off-list, NOT a
  bug**.

No parser script or intermediate CSV found on disk (gone / possibly on the VM).
Original parser is the one that produced the fusion artifacts.

---

## PARKED — consolidated master list (nothing dropped)

### A. Catalog seeding / SKU gap (the new top item)
1. **Re-extract the LMCP** cleanly (139-pp PDF, messy multi-column layout —
   same structure that broke the original parser). Build it as a careful,
   validated parse, not a one-pass. Output: structured `Drug | Form | Strength`.
2. **Diff LMCP-extract against DB** to produce two precise lists:
   (a) on-LMCP drugs missing SKUs → back-fill these (parser-miss recovery);
   (b) confirm which zero-SKU drugs are legitimately off-LMCP.
3. **Seed the recovered SKUs** — sourced only (never invent strength/form;
   land as `efda_approved=false`/pending for review). Validate on a small
   batch (~10 drugs) end-to-end before scaling. Mind unique
   `(drug_id, dosage_form, strength)` NULLS NOT DISTINCT.
4. **SKU-submission feature** — community model already in schema
   (`drug_sku.global_registry_status` pending, `approval_vote_count`,
   `submitted_by_group_id`). Bake in name-normalization + dedup-check before
   INSERT so new dupes/fusions can't recur (root-cause part 2).
5. Recount true gaps after back-fill.

### B. Catalog modeling (architecture — decide deliberately, don't rush)
6. **Non-drug products need their own track** — pharmacies sell more than the
   drug list: compounding ingredients (raw materials/excipients/bulk APIs) and
   non-drug retail (cosmetics, devices, supplies, baby products). Do NOT force
   these into the `drug` table. Design a general product/commodity model that
   CAN reference a drug when applicable but doesn't require it.
7. Devices already sitting in `drug` (condoms, Copper T380A IUD, contraceptive
   implants, KY jelly, gauze, etc.) are **legitimate retail items — keep them**;
   resolve only once the commodity model exists. **Never delete from the drug
   list on suspicion** (we only deleted in 09/11/12 because of hard evidence).
8. A few typo/near-dup stragglers spotted (low priority, verify before any
   action): "Acyclovir/acyclovir" (`133e5df6`) vs "Aciclovir" (`facec715`);
   "Pencilamine" (`dfea880d`) vs "Penicillamine" (`c0f48712`);
   "Leovonorgestrel (D-Nongestrel)" (`b265f337`); unbalanced parens in
   "Prussian Blue (Ferric hexacyanoferrate (II)" (`455da659`).
9. Cosmetic naming convention (slash vs paren) across survivors — lowest
   priority, no correctness stakes. Survey: 46 slash / 110 paren / 6 both.

### C. Frontend / checkout items (from original work order + COMPLIANCE_NOTES)
10. **VAT**: `drug_sku.is_vat_exempt` defaults true, but Sales checkout applied
    15% to an exempt drug. Checkout must honor SKU `is_vat_exempt`.
11. **Dispense → "Stock adjustment"** relabel + reason dropdown (Expired /
    Damaged / Lost / Returned to supplier). Keep transfers & customer-returns
    on their own paths. Reason may need a real column (not just notes) for
    reporting.
12. **Receive form → invoice-native**: packs × cost/pack → derived base qty &
    cost/unit, with reconciliation display. `pack_size` is the factor.
13. **Search-ranking bug**: pg_trgm on `inn_name` misses the populated twin when
    the common name is buried mid-string (was an issue pre-dedup; re-test now
    that twins are merged — may be reduced). Consider searching brand/synonyms
    or improving ranking so populated rows aren't cut by LIMIT.

### D. Trivial leftovers
14. Echo `reorder_level` in product GET response.
15. `classify_*.sql` one-time data scripts sit in `db/migrations/` — could move
    to `db/scripts/` for a clean migration chain.

---

## Quick-start for next session
```powershell
cd D:\Desktop\Projects\novadawa-api
$psql = "D:\pg18\pgsql\bin\psql.exe"
# set $env:DATABASE_URL for this terminal (doesn't persist across windows)
# run SQL via:  & $psql $env:DATABASE_URL -v ON_ERROR_STOP=1 -f <file>.sql
```
Current catalog: **1371 drugs, 2164 SKUs.** Console shows UTF-8 as cp437
mojibake — the DB data is fine.
