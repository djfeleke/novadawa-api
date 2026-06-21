"""
Inventory alerts — expiry & low-stock (read-only).

  GET /api/v1/inventory/branches/{branch_id}/alerts/expiry
        ?within_days=30&include_expired=true
      Active lots with stock expiring within N days, soonest first.
      include_expired=true also returns already-expired lots.

  GET /api/v1/inventory/branches/{branch_id}/alerts/low-stock?threshold=10
      Products whose total non-expired available is below `threshold`,
      lowest first. Includes out-of-stock products that have inventory
      history at the branch (total 0 < threshold). Threshold is supplied
      per request — there is no stored per-product reorder level yet
      (logged as a future enhancement).

Dates: expiry_date is a pure date, so "today" and days_to_expiry use the
local Addis date — (now() AT TIME ZONE 'Africa/Addis_Ababa')::date — so a
lot doesn't flip expiry status a day early near midnight UTC.

Shares the /api/v1/inventory prefix; registered in main.py.
"""
import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query

from app.auth.firebase import get_current_user
from app.database import get_db
from app.schemas.inventory_alerts import (
    ExpiryAlertLot,
    ExpiryAlertResponse,
    LowStockItem,
    LowStockResponse,
)

router = APIRouter(prefix="/api/v1/inventory", tags=["inventory"])

# Local (Addis) calendar date — single source of "today" for expiry math.
_TODAY = "(now() AT TIME ZONE 'Africa/Addis_Ababa')::date"


# —— Expiry ————————————————————————————————————————————————————————————————

@router.get("/branches/{branch_id}/alerts/expiry", response_model=ExpiryAlertResponse)
async def expiry_alerts(
    branch_id: str,
    within_days: int = Query(30, ge=0, le=3650),
    include_expired: bool = Query(True),
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Active lots with stock expiring within N days (optionally incl. expired)."""
    branch = await db.fetchval("SELECT id FROM branch WHERE id = $1", branch_id)
    if not branch:
        raise HTTPException(status_code=404, detail="Branch not found.")

    rows = await db.fetch(
        f"""
        SELECT i.id AS inventory_id, i.product_id, d.inn_name, p.brand_name,
               i.batch_number, i.expiry_date,
               (i.expiry_date - {_TODAY})   AS days_to_expiry,
               i.quantity_base_units,
               (i.expiry_date < {_TODAY})   AS is_expired
        FROM inventory i
        JOIN product p   ON p.id = i.product_id
        JOIN drug_sku ds ON ds.id = p.drug_sku_id
        JOIN drug d      ON d.id = ds.drug_id
        WHERE i.branch_id = $1
          AND i.is_active = true
          AND i.quantity_base_units > 0
          AND i.expiry_date <= {_TODAY} + $2::int
          AND ($3 OR i.expiry_date >= {_TODAY})
        ORDER BY i.expiry_date ASC
        """,
        branch_id, within_days, include_expired,
    )
    as_of = await db.fetchval(f"SELECT {_TODAY}")

    lots = [
        ExpiryAlertLot(
            inventory_id=str(r["inventory_id"]),
            product_id=str(r["product_id"]),
            inn_name=r["inn_name"],
            brand_name=r["brand_name"],
            batch_number=r["batch_number"],
            expiry_date=str(r["expiry_date"]),
            days_to_expiry=r["days_to_expiry"],
            quantity_base_units=r["quantity_base_units"],
            is_expired=r["is_expired"],
        )
        for r in rows
    ]

    return ExpiryAlertResponse(
        branch_id=branch_id,
        within_days=within_days,
        include_expired=include_expired,
        as_of_date=str(as_of),
        count=len(lots),
        lots=lots,
    )


# —— Low stock —————————————————————————————————————————————————————————————

@router.get("/branches/{branch_id}/alerts/low-stock", response_model=LowStockResponse)
async def low_stock_alerts(
    branch_id: str,
    threshold: int = Query(None, ge=0,
                           description="Explicit threshold for all products. "
                                       "Omit to use each product's reorder_level."),
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Products at a branch below an explicit threshold or their own reorder_level."""
    branch = await db.fetchval("SELECT id FROM branch WHERE id = $1", branch_id)
    if not branch:
        raise HTTPException(status_code=404, detail="Branch not found.")

    avail = f"""COALESCE(SUM(i.quantity_base_units) FILTER (
                    WHERE i.is_active = true
                      AND i.quantity_base_units > 0
                      AND i.expiry_date >= {_TODAY}
                ), 0)"""

    # $2 = explicit threshold, or NULL to fall back to each product's reorder_level.
    rows = await db.fetch(
        f"""
        SELECT p.id AS product_id, d.inn_name, p.brand_name, p.reorder_level,
               {avail} AS total_available
        FROM inventory i
        JOIN product p   ON p.id = i.product_id
        JOIN drug_sku ds ON ds.id = p.drug_sku_id
        JOIN drug d      ON d.id = ds.drug_id
        WHERE i.branch_id = $1
        GROUP BY p.id, d.inn_name, p.brand_name, p.reorder_level
        HAVING {avail} < COALESCE($2::int, p.reorder_level)
        ORDER BY total_available ASC
        """,
        branch_id, threshold,
    )
    as_of = await db.fetchval(f"SELECT {_TODAY}")

    items = [
        LowStockItem(
            product_id=str(r["product_id"]),
            inn_name=r["inn_name"],
            brand_name=r["brand_name"],
            total_available=r["total_available"],
            reorder_level=r["reorder_level"],
            threshold=threshold if threshold is not None else r["reorder_level"],
        )
        for r in rows
    ]

    return LowStockResponse(
        branch_id=branch_id,
        mode="param" if threshold is not None else "per_product",
        threshold=threshold,
        as_of_date=str(as_of),
        count=len(items),
        items=items,
    )
