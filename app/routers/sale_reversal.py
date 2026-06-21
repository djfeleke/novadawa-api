"""
Sale void / refund — atomic reversal of a completed sale.

  POST /api/v1/sales/{sale_id}/void
      Cancel a completed sale (typically same-day). Restores stock by default.

  POST /api/v1/sales/{sale_id}/refund
      Refund a completed sale (goods returned). Restores stock unless
      restock=false (damaged/unsellable goods).

Both share one transactional routine:
  1. SELECT ... FOR UPDATE on the sale; reject anything not 'completed'
     (blocks double-reversal).
  2. Controlled substances: reversal IS allowed and audited. If the sale
     contains a controlled substance, restock=true is REQUIRED (a damaged
     narcotic needs a separate wastage/EFDA process, not a silent loss).
     A narcotics_reversal row is written for each linked register entry so
     the controlled-substance trail stays reconstructable.
  3. For each sale_line, restore quantity_base_units to its EXACT inventory
     lot (FEFO/lot integrity), writing a 'return' inventory_movement
     (reference_type 'void'/'refund', notes = reason).
  4. Flip sale_status and stamp void_reason + voided_by_user_id.

Everything runs in a single transaction; any failure rolls the whole thing back.
"""
import asyncpg
from fastapi import APIRouter, Depends, HTTPException

from app.auth.firebase import get_current_user
from app.database import get_db
from app.schemas.sale_reversal import (
    ReversedLine,
    SaleReversalRequest,
    SaleReversalResponse,
)

router = APIRouter(prefix="/api/v1/sales", tags=["sales"])


async def _reverse_sale(
    sale_id: str,
    req: SaleReversalRequest,
    new_status: str,   # 'voided' | 'refunded'
    ref_type: str,     # 'void'   | 'refund'
    db: asyncpg.Connection,
) -> SaleReversalResponse:
    async with db.transaction():
        # 1) Lock the sale row; only a completed sale can be reversed.
        sale = await db.fetchrow(
            "SELECT id, sale_number, branch_id, sale_status "
            "FROM sale WHERE id = $1 FOR UPDATE",
            sale_id,
        )
        if not sale:
            raise HTTPException(status_code=404, detail="Sale not found.")
        if sale["sale_status"] != "completed":
            raise HTTPException(
                status_code=409,
                detail=(
                    f"Sale is '{sale['sale_status']}'. "
                    f"Only a completed sale can be {ref_type}ed."
                ),
            )

        # Validate the actor for a clean error (FK would otherwise 500).
        actor = await db.fetchval(
            "SELECT id FROM app_user WHERE id = $1", req.performed_by_user_id
        )
        if not actor:
            raise HTTPException(status_code=404, detail="performed_by_user_id not found.")

        # 2) Controlled-substance handling.
        controlled_flag = await db.fetchval(
            """
            SELECT EXISTS (
                SELECT 1
                FROM sale_line sl
                JOIN product p   ON p.id = sl.product_id
                JOIN drug_sku ds ON ds.id = p.drug_sku_id
                JOIN drug d      ON d.id = ds.drug_id
                WHERE sl.sale_id = $1
                  AND (d.controlled_substance OR ds.controlled_substance)
            )
            """,
            sale_id,
        )
        reg_entries = await db.fetch(
            """
            SELECT nr.id, nr.branch_id, nr.drug_sku_id,
                   nr.dispensed_quantity_base_units
            FROM narcotics_register nr
            JOIN sale_line sl ON sl.id = nr.sale_line_id
            WHERE sl.sale_id = $1
            """,
            sale_id,
        )
        is_controlled = controlled_flag or len(reg_entries) > 0
        if is_controlled and not req.restock:
            raise HTTPException(
                status_code=400,
                detail=(
                    "Controlled-substance reversal requires restock=true. "
                    "A damaged/unsellable narcotic must go through a separate "
                    "wastage/EFDA process, not a refund without restock."
                ),
            )

        # 3) Reverse each line.
        lines = await db.fetch(
            "SELECT id, inventory_id, product_id, quantity_base_units "
            "FROM sale_line WHERE sale_id = $1 ORDER BY id",
            sale_id,
        )

        reversed_lines: list[ReversedLine] = []
        total_restored = 0

        for ln in lines:
            restored = ln["quantity_base_units"]
            after = None

            if req.restock:
                cur = await db.fetchval(
                    "SELECT quantity_base_units FROM inventory WHERE id = $1 FOR UPDATE",
                    ln["inventory_id"],
                )
                if cur is None:
                    raise HTTPException(
                        status_code=409,
                        detail=f"Inventory lot {ln['inventory_id']} missing; cannot restock.",
                    )
                after = cur + restored
                await db.execute(
                    "UPDATE inventory SET quantity_base_units = $1 WHERE id = $2",
                    after, ln["inventory_id"],
                )
                await db.execute(
                    """
                    INSERT INTO inventory_movement
                        (inventory_id, branch_id, movement_type,
                         quantity_change_base_units, quantity_after_base_units,
                         reference_id, reference_type, notes, performed_by_user_id)
                    VALUES ($1, $2, 'return'::movement_type, $3, $4, $5, $6, $7, $8)
                    """,
                    ln["inventory_id"], sale["branch_id"],
                    restored, after, sale_id, ref_type, req.reason,
                    req.performed_by_user_id,
                )
                total_restored += restored

            reversed_lines.append(
                ReversedLine(
                    sale_line_id=str(ln["id"]),
                    inventory_id=str(ln["inventory_id"]),
                    product_id=str(ln["product_id"]),
                    restored_base_units=restored if req.restock else 0,
                    inventory_after_base_units=after,
                )
            )

        # 3b) Append-only narcotics reversal records (never mutate the register).
        narcotics_reversed = 0
        for e in reg_entries:
            await db.execute(
                """
                INSERT INTO narcotics_reversal
                    (narcotics_register_id, sale_id, branch_id, drug_sku_id,
                     reversed_quantity_base_units, reversal_type, reason,
                     reversed_by_user_id)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                """,
                e["id"], sale_id, e["branch_id"], e["drug_sku_id"],
                e["dispensed_quantity_base_units"], ref_type, req.reason,
                req.performed_by_user_id,
            )
            narcotics_reversed += 1

        # 4) Flip status + stamp reversal metadata.
        await db.execute(
            "UPDATE sale SET sale_status = $1::sale_status, void_reason = $2, "
            "voided_by_user_id = $3 WHERE id = $4",
            new_status, req.reason, req.performed_by_user_id, sale_id,
        )

    return SaleReversalResponse(
        sale_id=str(sale["id"]),
        sale_number=sale["sale_number"],
        sale_status=new_status,
        restocked=req.restock,
        lines_reversed=len(reversed_lines),
        total_restored_base_units=total_restored,
        narcotics_reversed_count=narcotics_reversed,
        reason=req.reason,
        performed_by_user_id=req.performed_by_user_id,
        lines=reversed_lines,
    )


@router.post("/{sale_id}/void", response_model=SaleReversalResponse)
async def void_sale(
    sale_id: str,
    req: SaleReversalRequest,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Void a completed sale (typically a same-day cancel). Restores stock by default."""
    return await _reverse_sale(sale_id, req, "voided", "void", db)


@router.post("/{sale_id}/refund", response_model=SaleReversalResponse)
async def refund_sale(
    sale_id: str,
    req: SaleReversalRequest,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Refund a completed sale (goods returned). Restores stock unless restock=false."""
    return await _reverse_sale(sale_id, req, "refunded", "refund", db)
