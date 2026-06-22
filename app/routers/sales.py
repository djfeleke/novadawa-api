"""
Sale endpoints — atomic checkout with FEFO dispense and narcotics compliance.

  POST /api/v1/sales/branches/{branch_id}/checkout
      Atomic checkout: validates stock, FEFO-dispenses across lots,
      creates sale + sale_lines + inventory movements, and writes
      narcotics_register entries for controlled substances — all in
      a single transaction that rolls back on any failure.
"""

import uuid

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status

from app.auth.firebase import get_current_user
from app.database import get_db
from app.schemas.sale import (
    CheckoutRequest,
    CheckoutResponse,
    SaleLineResponse,
)

router = APIRouter(prefix="/api/v1/sales", tags=["sales"])

VAT_RATE_BPS = 1500  # 15% — Ethiopian standard


@router.post(
    "/branches/{branch_id}/checkout",
    response_model=CheckoutResponse,
    status_code=status.HTTP_201_CREATED,
)
async def checkout(
    branch_id: str,
    req: CheckoutRequest,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """
    Complete a pharmacy sale in a single atomic transaction.

    For each line item:
    1. Resolves product -> sale_unit_size for base-unit conversion
    2. Checks controlled-substance flag; rejects if narcotics info missing
    3. FEFO dispense with FOR UPDATE row locking
    4. Creates sale_line(s) — one per inventory lot touched
    5. Records inventory_movement (type='sale')
    6. Writes narcotics_register for controlled substances

    Controlled-substance lines require narcotics info. Individual human-supplied
    fields (patient/prescriber/prescription) may be omitted only when the
    narcotics payload carries an override_reason; the dispense is then recorded
    as an audited exception (override_reason + overridden_by_user_id).

    Hard-rejects (400) if any product has insufficient non-expired stock
    or a controlled substance line lacks narcotics info entirely.
    """
    # Validate branch exists
    branch = await db.fetchval("SELECT id FROM branch WHERE id = $1", branch_id)
    if not branch:
        raise HTTPException(status_code=404, detail="Branch not found.")

    sale_number = f"S-{uuid.uuid4().hex[:8].upper()}"
    dispensing_user = req.dispensed_by_user_id or req.cashier_user_id

    async with db.transaction():

        # ── Phase 1: pre-validate all products & controlled status ──

        line_meta = []
        for i, line in enumerate(req.lines):
            meta = await db.fetchrow(
                """
                SELECT p.id AS product_id, p.sale_unit_size, p.drug_sku_id,
                       (d.controlled_substance OR ds.controlled_substance)
                           AS controlled_substance,
                       d.inn_name
                FROM product p
                JOIN drug_sku ds ON ds.id = p.drug_sku_id
                JOIN drug d ON d.id = ds.drug_id
                WHERE p.id = $1
                """,
                line.product_id,
            )
            if not meta:
                raise HTTPException(400, detail=f"Product not found: {line.product_id}")

            if meta["controlled_substance"] and not line.narcotics:
                raise HTTPException(
                    400,
                    detail=(
                        f"Line {i + 1} ({meta['inn_name']}) is a controlled substance "
                        "— narcotics info required."
                    ),
                )
            line_meta.append(meta)

        # ── Phase 2: FEFO dispense & collect sale-line data ──

        pending_lines: list[dict] = []
        subtotal_santim = 0
        vat_total_santim = 0

        for line, meta in zip(req.lines, line_meta):
            qty_base_needed = line.quantity_sale_units * meta["sale_unit_size"]

            # Lock non-expired active lots, oldest expiry first
            lots = await db.fetch(
                """
                SELECT id, batch_number, expiry_date, quantity_base_units,
                       selling_price_per_sale_unit_santim, cost_per_base_unit_santim
                FROM inventory
                WHERE branch_id = $1 AND product_id = $2
                  AND quantity_base_units > 0 AND is_active = true
                  AND expiry_date >= CURRENT_DATE
                ORDER BY expiry_date ASC
                FOR UPDATE
                """,
                branch_id, line.product_id,
            )

            available = sum(r["quantity_base_units"] for r in lots)
            if available < qty_base_needed:
                raise HTTPException(
                    400,
                    detail={
                        "error": "insufficient_stock",
                        "product_id": line.product_id,
                        "requested_base_units": qty_base_needed,
                        "available_base_units": available,
                    },
                )

            remaining = qty_base_needed
            for lot in lots:
                if remaining <= 0:
                    break

                take_base = min(lot["quantity_base_units"], remaining)
                new_qty = lot["quantity_base_units"] - take_base

                # Decrement inventory immediately (within the transaction)
                await db.execute(
                    "UPDATE inventory SET quantity_base_units = $1 WHERE id = $2",
                    new_qty, lot["id"],
                )

                # Pricing — compute per-lot-split
                # line_subtotal is pro-rated from the per-sale-unit price
                sale_unit_size = meta["sale_unit_size"]
                unit_price = lot["selling_price_per_sale_unit_santim"]
                line_sub = unit_price * take_base // sale_unit_size
                vat_amt = (line_sub * VAT_RATE_BPS // 10000) if line.is_vat_applicable else 0
                line_total = line_sub + vat_amt
                cogs = take_base * lot["cost_per_base_unit_santim"]
                margin = line_sub - cogs

                # sale_line.quantity_sale_units: best-effort conversion
                take_sale = take_base // sale_unit_size if sale_unit_size > 1 else take_base
                # If the split doesn't divide evenly, store base units
                # (last lot in a chain absorbs any rounding)
                if sale_unit_size > 1 and take_base % sale_unit_size != 0:
                    take_sale = take_base

                pending_lines.append({
                    "inventory_id": lot["id"],
                    "product_id": line.product_id,
                    "batch_number": lot["batch_number"],
                    "take_base": take_base,
                    "take_sale": take_sale,
                    "new_qty": new_qty,
                    "unit_price_santim": unit_price,
                    "line_subtotal_santim": line_sub,
                    "is_vat_applicable": line.is_vat_applicable,
                    "vat_rate_bps": VAT_RATE_BPS if line.is_vat_applicable else 0,
                    "vat_amount_santim": vat_amt,
                    "line_total_santim": line_total,
                    "cogs_santim": cogs,
                    "gross_margin_santim": margin,
                    "is_controlled": meta["controlled_substance"],
                    "drug_sku_id": meta["drug_sku_id"],
                    "narcotics": line.narcotics,
                })

                subtotal_santim += line_sub
                vat_total_santim += vat_amt
                remaining -= take_base

        total_santim = subtotal_santim + vat_total_santim - req.discount_santim

        # ── Phase 3: create sale record ──

        sale = await db.fetchrow(
            """
            INSERT INTO sale
                (branch_id, sale_number, cashier_user_id, dispensed_by_user_id,
                 customer_name, customer_phone,
                 prescription_ref, prescription_image_url,
                 subtotal_santim, vat_total_santim, discount_santim, total_santim,
                 payment_method, payment_reference)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12,
                    $13::payment_method, $14)
            RETURNING *
            """,
            branch_id, sale_number, req.cashier_user_id,
            req.dispensed_by_user_id, req.customer_name, req.customer_phone,
            req.prescription_ref, req.prescription_image_url,
            subtotal_santim, vat_total_santim, req.discount_santim, total_santim,
            req.payment_method, req.payment_reference,
        )

        # ── Phase 4: create sale_lines, movements, narcotics entries ──

        response_lines: list[SaleLineResponse] = []
        narcotics_count = 0
        narcotics_overrides = 0

        for sl in pending_lines:
            # Sale line
            sale_line = await db.fetchrow(
                """
                INSERT INTO sale_line
                    (sale_id, inventory_id, product_id,
                     quantity_sale_units, quantity_base_units,
                     unit_price_santim, line_subtotal_santim,
                     is_vat_applicable, vat_rate_bps, vat_amount_santim,
                     line_total_santim, cogs_santim, gross_margin_santim)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
                RETURNING *
                """,
                sale["id"], sl["inventory_id"], sl["product_id"],
                sl["take_sale"], sl["take_base"],
                sl["unit_price_santim"], sl["line_subtotal_santim"],
                sl["is_vat_applicable"], sl["vat_rate_bps"],
                sl["vat_amount_santim"], sl["line_total_santim"],
                sl["cogs_santim"], sl["gross_margin_santim"],
            )

            # Inventory movement — references the sale
            await db.execute(
                """
                INSERT INTO inventory_movement
                    (inventory_id, branch_id, movement_type,
                     quantity_change_base_units, quantity_after_base_units,
                     reference_id, reference_type, performed_by_user_id)
                VALUES ($1, $2, 'sale'::movement_type, $3, $4, $5, 'sale', $6)
                """,
                sl["inventory_id"], branch_id,
                -sl["take_base"], sl["new_qty"],
                sale["id"], dispensing_user,
            )

            # Narcotics register for controlled substances
            if sl["is_controlled"] and sl["narcotics"]:
                narc = sl["narcotics"]

                # Running balance: total remaining for this drug_sku at branch
                # (reads post-decrement values since we're in the same txn)
                running_bal = await db.fetchval(
                    """
                    SELECT COALESCE(SUM(i.quantity_base_units), 0)
                    FROM inventory i
                    JOIN product p ON p.id = i.product_id
                    WHERE i.branch_id = $1 AND p.drug_sku_id = $2
                      AND i.is_active = true
                    """,
                    branch_id, sl["drug_sku_id"],
                )

                # Override bookkeeping: when a reason is given, missing human
                # fields are permitted and we stamp the authorising pharmacist.
                override_reason = getattr(narc, "override_reason", None)
                overridden_by = dispensing_user if override_reason else None
                if override_reason:
                    narcotics_overrides += 1

                await db.execute(
                    """
                    INSERT INTO narcotics_register
                        (sale_line_id, branch_id, drug_sku_id,
                         dispensed_quantity_base_units, dispensed_by_user_id,
                         patient_full_name, patient_age, patient_sex,
                         patient_address, patient_id_type,
                         patient_id_number, prescribing_doctor_name,
                         prescribing_doctor_license, prescription_serial,
                         prescription_image_url, running_balance_base_units,
                         override_reason, overridden_by_user_id)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9,
                            $10::patient_id_type, $11, $12, $13, $14, $15, $16,
                            $17, $18)
                    """,
                    sale_line["id"], branch_id, sl["drug_sku_id"],
                    sl["take_base"], dispensing_user,
                    narc.patient_full_name, narc.patient_age, narc.patient_sex,
                    narc.patient_address, narc.patient_id_type,
                    narc.patient_id_number, narc.prescribing_doctor_name,
                    narc.prescribing_doctor_license, narc.prescription_serial,
                    narc.prescription_image_url, running_bal,
                    override_reason, overridden_by,
                )
                narcotics_count += 1

            response_lines.append(SaleLineResponse(
                sale_line_id=str(sale_line["id"]),
                product_id=str(sale_line["product_id"]),
                inventory_id=str(sale_line["inventory_id"]),
                batch_number=sl["batch_number"],
                quantity_sale_units=sale_line["quantity_sale_units"],
                quantity_base_units=sale_line["quantity_base_units"],
                unit_price_santim=sale_line["unit_price_santim"],
                line_subtotal_santim=sale_line["line_subtotal_santim"],
                vat_amount_santim=sale_line["vat_amount_santim"],
                line_total_santim=sale_line["line_total_santim"],
            ))

    return CheckoutResponse(
        sale_id=str(sale["id"]),
        sale_number=sale["sale_number"],
        branch_id=branch_id,
        subtotal_santim=subtotal_santim,
        vat_total_santim=vat_total_santim,
        discount_santim=req.discount_santim,
        total_santim=total_santim,
        payment_method=req.payment_method,
        sale_status=sale["sale_status"],
        lines=response_lines,
        narcotics_entries=narcotics_count,
        narcotics_overrides=narcotics_overrides,
    )
