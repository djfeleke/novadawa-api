# Tier 3 — numbered-list fusion rows (deferred from migration 11, 2026-06-24)

## What they are
7 `drug` rows where an ingestion bug welded the END of one drug + a list-number
+ the START of the next into one name. All carry SKUs, but the SKUs are ALSO
misaligned (chemo drugs with ointment/capsule forms that don't exist IRL).
Downstream products = 0 on all (verified). None are narcotics. Mostly
hospital-only oncology — low retail stakes.

## The rows (fused_id | name | sku_count)
- 0c3285b8 | Carboplatin 11. Carmustine | 3   (incl. bogus 20mg Ointment)
- 3721c9af | Etoposide 23. Fludarabine | 6
- 5eb396f4 | Express Tube 11. 5-Flurouracil | 1   ("Express Tube" not a drug)
- 49c71ba5 | Fluorouracil 25. Gemcitabine | 3
- 8c280470 | Vincristine Sulphate 45. Vinorelbine | 5   (incl. bogus 30mg Capsule)
- b09eca75 | Sodium Chloride 16. Sodium Chloride + KCl + citrate + glucose | 4
- ae368c11 | Lactated Potassium Saline (Darrow's) 10.. Lactated Ringer's (Hartmann's) | 5

## Clean standalone rows already exist (mostly empty)
Carboplatin 7c9db6d0(0), Etoposide a22b1518(0), Fludarabine 8ab81755(0),
Fluorouracil b97b263c(3 real), Gemcitabine 6e9f5f22(0), Vincristine 4fcfa51b(0),
Vinorelbine 1a6d4865(0), Sodium Chloride 0941b6dc(1).
=> The real drugs are present. The fused rows are corrupt duplicates with junk SKUs.

## Why no automated split
SKUs can't be confidently assigned to either half (strengths/forms are
implausible — ingestion misaligned them too). No trustworthy signal.

## Decision needed next session (pick one)
A. DELETE the 7 fused rows + their junk SKUs outright. Lose nothing real
   (standalones remain; SKUs were garbage). Cleanest. Recommended.
B. Manually triage each SKU -> reassign the few plausible ones to the correct
   standalone row, then delete the husk. Higher effort, marginal gain.

## Discipline
Destructive SKU delete. Same as 09: backup first, BEGIN/ROLLBACK preview,
verify product-ref = 0 still holds, COMMIT. Not a session-tail job.

## Also still open (cosmetic, separate)
Uniform naming convention (slash vs paren) across all ~1376 drugs. Survey:
46 slash / 110 paren / 6 both. Pure UPDATE, no FK risk. Lowest priority.