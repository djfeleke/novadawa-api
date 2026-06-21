"""
Drug interaction checker.

  POST /api/v1/interactions/check
      Screen a basket of product IDs for known drug-drug interactions.
      Resolves each product -> drug_sku -> drug, then looks up the global
      drug_interaction_cache for any pair where BOTH drugs are in the basket.
      Results are ordered most-severe first.

  Safety note: any product_id that does not resolve to a catalog drug is
  returned in `unresolved_product_ids`. A non-empty list there means the
  basket was NOT fully screened — the caller must surface that, not treat an
  empty `flags` list as "all clear".
"""
import asyncpg
from fastapi import APIRouter, Depends

from app.auth.firebase import get_current_user
from app.database import get_db
from app.schemas.interaction import (
    InteractionCheckRequest,
    InteractionCheckResponse,
    InteractionFlag,
)

router = APIRouter(prefix="/api/v1/interactions", tags=["interactions"])


@router.post("/check", response_model=InteractionCheckResponse)
async def check_interactions(
    req: InteractionCheckRequest,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Screen a basket of products for drug-drug interactions."""
    # Dedup input, preserve caller order.
    input_ids = list(dict.fromkeys(req.product_ids))

    # 1) Resolve products -> drugs. Missing products simply don't come back.
    rows = await db.fetch(
        """
        SELECT p.id AS product_id, d.id AS drug_id, d.inn_name
        FROM product p
        JOIN drug_sku ds ON ds.id = p.drug_sku_id
        JOIN drug d      ON d.id = ds.drug_id
        WHERE p.id = ANY($1::uuid[])
        """,
        input_ids,
    )

    resolved_ids: set[str] = set()
    drug_to_products: dict[str, list[str]] = {}
    for r in rows:
        pid, did = str(r["product_id"]), str(r["drug_id"])
        resolved_ids.add(pid)
        drug_to_products.setdefault(did, []).append(pid)

    unresolved = [pid for pid in input_ids if pid not in resolved_ids]
    distinct_drug_ids = list(drug_to_products.keys())

    # Fewer than two distinct drugs -> no pair possible.
    if len(distinct_drug_ids) < 2:
        return InteractionCheckResponse(
            interaction_count=0,
            highest_severity=None,
            flags=[],
            checked_product_ids=sorted(resolved_ids),
            unresolved_product_ids=unresolved,
        )

    # 2) Cached interactions where BOTH drugs are in the basket.
    #    Order-agnostic; most-severe first (enum order, not alphabetical).
    interaction_rows = await db.fetch(
        """
        SELECT drug_a_id, drug_b_id, drug_a_name, drug_b_name, severity, source
        FROM drug_interaction_cache
        WHERE drug_a_id = ANY($1::uuid[])
          AND drug_b_id = ANY($1::uuid[])
        ORDER BY severity DESC
        """,
        distinct_drug_ids,
    )

    # 3) Build flags, collapsing symmetric pairs (first kept = most severe).
    flags: list[InteractionFlag] = []
    seen: set[frozenset] = set()
    for r in interaction_rows:
        a, b = str(r["drug_a_id"]), str(r["drug_b_id"])
        key = frozenset((a, b))
        if key in seen:
            continue
        seen.add(key)
        flags.append(
            InteractionFlag(
                severity=r["severity"],
                drug_a_id=a,
                drug_a_name=r["drug_a_name"],
                drug_b_id=b,
                drug_b_name=r["drug_b_name"],
                source=r["source"],
                products_a=drug_to_products.get(a, []),
                products_b=drug_to_products.get(b, []),
            )
        )

    return InteractionCheckResponse(
        interaction_count=len(flags),
        highest_severity=flags[0].severity if flags else None,
        flags=flags,
        checked_product_ids=sorted(resolved_ids),
        unresolved_product_ids=unresolved,
    )
