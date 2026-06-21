"""
Inventory adjustments & transfers — non-sale stock movements.

  POST /api/v1/inventory/lots/{inventory_id}/adjust
      Wastage, expired removal, or manual count correction on a single lot.
      Writes a wastage/expired/adjustment movement and updates the lot.

  POST /api/v1/inventory/lots/{inventory_id}/transfer
      Move stock from one branch to another. Atomically decrements the
      source lot (transfer_out) and creates a mirrored lot at the
      destination branch (transfer_in), linked by a shared transfer_id.

Movement-type usage across the system:
  purchase (receive) · sale (checkout/dispense) · return (void/refund) ·
  wastage · expired · adjustment · transfer_out · transfer_in   <- this module.

Shares the /api/v1/inventory prefix with the receive/dispense router but
lives in a separate module; registered in main.py.
"""
import uuid

import asyncpg
from fastapi import APIRouter, Depends, HTTPException

from app.auth.firebase import get_current_user
from app.database import get_db
from app.schemas.inventory_adjust import (
    LotAdjustRequest,
    LotAdjustResponse,
    LotTransferRequest,
    LotTransferResponse,
)

router = APIRouter(prefix="/api/v1/inventory", tags=["inventory"])


# —— Adjust ————————————————————————————————————————————————————————————————

@router.post("/lots/{inventory_id}/adjust", response_model=LotAdjustResponse)
async def adjust_lot(
    inventory_id: str,
    req: LotAdjustRequest,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Wastage / expired removal / manual correction on a single inventory lot."""
    delta = req.quantity_change_base_units
    mt = req.movement_type

    # Sign rules.
    if mt in ("wastage", "expired") and delta >= 0:
        raise HTTPException(
            status_code=400,
            detail=f"'{mt}' must remove stock (negative quantity_change_base_units).",
        )
    if mt == "adjustment" and delta == 0:
        raise HTTPException(
            status_code=400,
            detail="'adjustment' requires a non-zero quantity_change_base_units.",
        )

    async with db.transaction():
        lot = await db.fetchrow(
            """
            SELECT id, branch_id, product_id, quantity_base_units,
                   (expiry_date < CURRENT_DATE) AS is_expired
            FROM inventory WHERE id = $1 FOR UPDATE
            """,
            inventory_id,
        )
        if not lot:
            raise HTTPException(status_code=404, detail="Inventory lot not found.")

        actor = await db.fetchval(
            "SELECT id FROM app_user WHERE id = $1", req.performed_by_user_id
        )
        if not actor:
            raise HTTPException(status_code=404, detail="performed_by_user_id not found.")

        if mt == "expired" and not lot["is_expired"]:
            raise HTTPException(
                status_code=400,
                detail="'expired' removal requires the lot to be past its expiry_date.",
            )

        new_qty = lot["quantity_base_units"] + delta
        if new_qty < 0:
            raise HTTPException(
                status_code=400,
                detail={
                    "error": "insufficient_stock",
                    "current": lot["quantity_base_units"],
                    "requested_change": delta,
                },
            )

        await db.execute(
            "UPDATE inventory SET quantity_base_units = $1 WHERE id = $2",
            new_qty, inventory_id,
        )
        mov = await db.fetchrow(
            """
            INSERT INTO inventory_movement
                (inventory_id, branch_id, movement_type,
                 quantity_change_base_units, quantity_after_base_units,
                 reference_id, reference_type, notes, performed_by_user_id)
            VALUES ($1, $2, $3::movement_type, $4, $5, NULL, NULL, $6, $7)
            RETURNING id
            """,
            inventory_id, lot["branch_id"], mt, delta, new_qty,
            req.reason, req.performed_by_user_id,
        )

    return LotAdjustResponse(
        inventory_id=str(lot["id"]),
        branch_id=str(lot["branch_id"]),
        product_id=str(lot["product_id"]),
        movement_type=mt,
        quantity_change_base_units=delta,
        quantity_after_base_units=new_qty,
        reason=req.reason,
        performed_by_user_id=req.performed_by_user_id,
        movement_id=str(mov["id"]),
    )


# —— Transfer ——————————————————————————————————————————————————————————————

@router.post("/lots/{inventory_id}/transfer", response_model=LotTransferResponse)
async def transfer_lot(
    inventory_id: str,
    req: LotTransferRequest,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Move stock from one branch to another (atomic transfer_out + transfer_in)."""
    async with db.transaction():
        src = await db.fetchrow(
            """
            SELECT id, branch_id, product_id, quantity_base_units, is_active,
                   (expiry_date < CURRENT_DATE) AS is_expired
            FROM inventory WHERE id = $1 FOR UPDATE
            """,
            inventory_id,
        )
        if not src:
            raise HTTPException(status_code=404, detail="Source inventory lot not found.")

        actor = await db.fetchval(
            "SELECT id FROM app_user WHERE id = $1", req.performed_by_user_id
        )
        if not actor:
            raise HTTPException(status_code=404, detail="performed_by_user_id not found.")

        dest_branch = await db.fetchval(
            "SELECT id FROM branch WHERE id = $1", req.to_branch_id
        )
        if not dest_branch:
            raise HTTPException(status_code=404, detail="Destination branch not found.")

        if str(src["branch_id"]) == str(req.to_branch_id):
            raise HTTPException(status_code=400, detail="Cannot transfer to the same branch.")
        if src["is_expired"]:
            raise HTTPException(status_code=400, detail="Cannot transfer expired stock.")
        if not src["is_active"]:
            raise HTTPException(status_code=400, detail="Source lot is inactive.")
        if src["quantity_base_units"] < req.quantity_base_units:
            raise HTTPException(
                status_code=400,
                detail={
                    "error": "insufficient_stock",
                    "available": src["quantity_base_units"],
                    "requested": req.quantity_base_units,
                },
            )

        transfer_id = str(uuid.uuid4())
        new_src = src["quantity_base_units"] - req.quantity_base_units

        # Decrement source + log transfer_out.
        await db.execute(
            "UPDATE inventory SET quantity_base_units = $1 WHERE id = $2",
            new_src, inventory_id,
        )
        await db.execute(
            """
            INSERT INTO inventory_movement
                (inventory_id, branch_id, movement_type,
                 quantity_change_base_units, quantity_after_base_units,
                 reference_id, reference_type, notes, performed_by_user_id)
            VALUES ($1, $2, 'transfer_out'::movement_type, $3, $4,
                    $5, 'transfer', $6, $7)
            """,
            inventory_id, src["branch_id"], -req.quantity_base_units, new_src,
            transfer_id, req.reason, req.performed_by_user_id,
        )

        # Create destination lot mirroring the source, then log transfer_in.
        dest = await db.fetchrow(
            """
            INSERT INTO inventory
                (branch_id, product_id, batch_number, expiry_date,
                 quantity_base_units, cost_per_base_unit_santim,
                 exchange_rate_at_purchase, selling_price_per_sale_unit_santim,
                 supplier_id, purchase_order_ref, received_by_user_id, is_active)
            SELECT $1, product_id, batch_number, expiry_date,
                   $2, cost_per_base_unit_santim,
                   exchange_rate_at_purchase, selling_price_per_sale_unit_santim,
                   supplier_id, purchase_order_ref, $3, true
            FROM inventory WHERE id = $4
            RETURNING id
            """,
            req.to_branch_id, req.quantity_base_units, req.performed_by_user_id,
            inventory_id,
        )
        dest_id = dest["id"]

        await db.execute(
            """
            INSERT INTO inventory_movement
                (inventory_id, branch_id, movement_type,
                 quantity_change_base_units, quantity_after_base_units,
                 reference_id, reference_type, notes, performed_by_user_id)
            VALUES ($1, $2, 'transfer_in'::movement_type, $3, $3,
                    $4, 'transfer', $5, $6)
            """,
            dest_id, req.to_branch_id, req.quantity_base_units,
            transfer_id, req.reason, req.performed_by_user_id,
        )

    return LotTransferResponse(
        transfer_id=transfer_id,
        product_id=str(src["product_id"]),
        quantity_base_units=req.quantity_base_units,
        source_inventory_id=str(src["id"]),
        source_branch_id=str(src["branch_id"]),
        source_quantity_after=new_src,
        dest_inventory_id=str(dest_id),
        dest_branch_id=str(req.to_branch_id),
        dest_quantity=req.quantity_base_units,
        reason=req.reason,
        performed_by_user_id=req.performed_by_user_id,
    )
