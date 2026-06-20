"""
Inventory endpoints — receive, dispense, and stock queries.

  POST /api/v1/inventory/branches/{branch_id}/receive
      Record a new batch arriving at a branch. Creates an inventory row
      and a 'purchase' movement in a single transaction.

  POST /api/v1/inventory/branches/{branch_id}/dispense
      Dispense stock using FEFO (First Expired, First Out). Rejects with
      400 if available (non-expired, active) stock is insufficient.
      Decrements across lots oldest-expiry-first within a locked
      transaction to prevent race conditions.

  GET  /api/v1/inventory/branches/{branch_id}/stock?product_id=...
      Returns per-lot stock breakdown and total available quantity.
"""

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.auth.firebase import get_current_user
from app.database import get_db
from app.schemas.inventory import (
    DispenseLotDetail,
    DispenseRequest,
    DispenseResponse,
    ReceiveRequest,
    ReceiveResponse,
    StockLot,
    StockResponse,
)

router = APIRouter(prefix="/api/v1/inventory", tags=["inventory"])


# —— Receive ——————————————————————————————————————————————————————————

@router.post(
    "/branches/{branch_id}/receive",
    response_model=ReceiveResponse,
    status_code=status.HTTP_201_CREATED,
)
async def receive_stock(
    branch_id: str,
    req: ReceiveRequest,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """
    Record a new batch arriving at a branch.

    Each call creates a new inventory row (even for the same product +
    batch_number) because separate receipts may have different costs or
    suppliers. The purchase_order_ref field lets callers track provenance.
    """
    # Verify branch exists
    branch = await db.fetchval("SELECT id FROM branch WHERE id = $1", branch_id)
    if not branch:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Branch not found.")

    # Verify product exists
    product = await db.fetchval("SELECT id FROM product WHERE id = $1", req.product_id)
    if not product:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found.")

    async with db.transaction():
        # 1. Create inventory row (one row per batch receipt)
        inv = await db.fetchrow(
            """
            INSERT INTO inventory
                (branch_id, product_id, batch_number, expiry_date,
                 quantity_base_units, cost_per_base_unit_santim,
                 exchange_rate_at_purchase, selling_price_per_sale_unit_santim,
                 supplier_id, purchase_order_ref, received_by_user_id)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
            RETURNING *
            """,
            branch_id, req.product_id, req.batch_number, req.expiry_date,
            req.quantity_base_units, req.cost_per_base_unit_santim,
            req.exchange_rate_at_purchase,
            req.selling_price_per_sale_unit_santim,
            req.supplier_id, req.purchase_order_ref, req.received_by_user_id,
        )

        # 2. Record movement
        mov = await db.fetchrow(
            """
            INSERT INTO inventory_movement
                (inventory_id, branch_id, movement_type,
                 quantity_change_base_units, quantity_after_base_units,
                 reference_id, reference_type, notes, performed_by_user_id)
            VALUES ($1, $2, 'purchase'::movement_type,
                    $3, $3,
                    NULL, NULL, $4, $5)
            RETURNING *
            """,
            inv["id"], branch_id,
            req.quantity_base_units,
            req.notes, req.received_by_user_id,
        )

    return ReceiveResponse(
        inventory_id=str(inv["id"]),
        movement_id=str(mov["id"]),
        branch_id=str(inv["branch_id"]),
        product_id=str(inv["product_id"]),
        batch_number=inv["batch_number"],
        expiry_date=str(inv["expiry_date"]),
        quantity_base_units=inv["quantity_base_units"],
        received_at=str(inv["received_at"]),
    )


# —— Dispense (FEFO) ——————————————————————————————————————————————————

@router.post(
    "/branches/{branch_id}/dispense",
    response_model=DispenseResponse,
)
async def dispense_stock(
    branch_id: str,
    req: DispenseRequest,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """
    Dispense stock using FEFO (First Expired, First Out).

    Locks eligible inventory rows (FOR UPDATE) to prevent concurrent
    dispenses from racing past the availability check. Returns 400 if
    the total available (non-expired, active) quantity is less than
    the requested amount.
    """
    async with db.transaction():
        # Lock non-expired, active lots — oldest expiry first.
        # FOR UPDATE serializes concurrent dispenses on the same rows
        # so the availability check cannot be raced.
        lots = await db.fetch(
            """
            SELECT id, batch_number, expiry_date, quantity_base_units
            FROM inventory
            WHERE branch_id = $1
              AND product_id = $2
              AND quantity_base_units > 0
              AND is_active = true
              AND expiry_date >= CURRENT_DATE
            ORDER BY expiry_date ASC
            FOR UPDATE
            """,
            branch_id, req.product_id,
        )

        available = sum(r["quantity_base_units"] for r in lots)
        if available < req.quantity_base_units:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={
                    "error": "insufficient_stock",
                    "requested": req.quantity_base_units,
                    "available": available,
                },
            )

        remaining = req.quantity_base_units
        dispensed_lots: list[DispenseLotDetail] = []

        for lot in lots:
            if remaining <= 0:
                break

            take = min(lot["quantity_base_units"], remaining)
            new_qty = lot["quantity_base_units"] - take

            # Decrement the lot
            await db.execute(
                "UPDATE inventory SET quantity_base_units = $1 WHERE id = $2",
                new_qty, lot["id"],
            )

            # Record movement with running-balance snapshot
            await db.execute(
                """
                INSERT INTO inventory_movement
                    (inventory_id, branch_id, movement_type,
                     quantity_change_base_units, quantity_after_base_units,
                     reference_id, reference_type, notes, performed_by_user_id)
                VALUES ($1, $2, 'sale'::movement_type,
                        $3, $4,
                        $5, $6, $7, $8)
                """,
                lot["id"], branch_id,
                -take, new_qty,
                req.sale_id, "sale" if req.sale_id else None,
                req.notes, req.performed_by_user_id,
            )

            dispensed_lots.append(DispenseLotDetail(
                inventory_id=str(lot["id"]),
                batch_number=lot["batch_number"],
                expiry_date=str(lot["expiry_date"]),
                quantity_taken=take,
                quantity_remaining=new_qty,
            ))

            remaining -= take

    return DispenseResponse(
        product_id=req.product_id,
        quantity_dispensed=req.quantity_base_units,
        lots=dispensed_lots,
    )


# —— Stock query ——————————————————————————————————————————————————————

@router.get(
    "/branches/{branch_id}/stock",
    response_model=StockResponse,
)
async def get_stock(
    branch_id: str,
    product_id: str = Query(..., description="Product to check stock for"),
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """
    Returns per-lot stock breakdown for a product at a branch.

    Shows all active lots (including expired ones, flagged). The
    total_available count excludes expired lots.
    """
    lots = await db.fetch(
        """
        SELECT id, batch_number, expiry_date, quantity_base_units,
               selling_price_per_sale_unit_santim,
               (expiry_date < CURRENT_DATE) AS is_expired
        FROM inventory
        WHERE branch_id = $1
          AND product_id = $2
          AND is_active = true
          AND quantity_base_units > 0
        ORDER BY expiry_date ASC
        """,
        branch_id, product_id,
    )

    total_available = sum(
        r["quantity_base_units"] for r in lots if not r["is_expired"]
    )

    return StockResponse(
        branch_id=branch_id,
        product_id=product_id,
        total_available=total_available,
        lots=[
            StockLot(
                inventory_id=str(r["id"]),
                batch_number=r["batch_number"],
                expiry_date=str(r["expiry_date"]),
                quantity_base_units=r["quantity_base_units"],
                is_expired=r["is_expired"],
                selling_price_per_sale_unit_santim=r["selling_price_per_sale_unit_santim"],
            )
            for r in lots
        ],
    )
