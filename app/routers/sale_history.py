"""
Sale history & detail — read-only reporting for reconciliation.

  GET /api/v1/sales/branches/{branch_id}
      List sales for a branch, filtered by status, payment method,
      date range (local Ethiopian day by default), cashier, or free-text
      (sale number / customer name / phone). Paginated, newest first.
      Returns the page PLUS total_count and total_santim_sum for the full
      filtered set (end-of-day reconciliation).

  GET /api/v1/sales/{sale_id}
      Full sale detail with line items (the receipt view).

Note: shares the /api/v1/sales prefix with the checkout router but lives in
a separate module; both are registered in main.py.
"""
from datetime import date
from typing import Literal, Optional

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query

from app.auth.firebase import get_current_user
from app.database import get_db
from app.schemas.sale_history import (
    SaleDetailResponse,
    SaleHistoryResponse,
    SaleLineDetail,
    SaleSummary,
)

router = APIRouter(prefix="/api/v1/sales", tags=["sales"])

# Shared WHERE clause for the list + aggregate queries (params $1..$8).
#   $1 branch_id   $2 status        $3 payment_method  $4 date_from
#   $5 date_to     $6 tz            $7 cashier_user_id $8 search pattern
_SALE_FILTER = """
    FROM sale s
    WHERE s.branch_id = $1
      AND ($2::sale_status IS NULL OR s.sale_status = $2)
      AND ($3::payment_method IS NULL OR s.payment_method = $3)
      AND ($4::date IS NULL OR (s.created_at AT TIME ZONE $6)::date >= $4)
      AND ($5::date IS NULL OR (s.created_at AT TIME ZONE $6)::date <= $5)
      AND ($7::uuid IS NULL OR s.cashier_user_id = $7)
      AND ($8::text IS NULL
           OR s.sale_number ILIKE $8
           OR s.customer_name ILIKE $8
           OR s.customer_phone ILIKE $8)
"""


# —— List / filter ——————————————————————————————————————————————————————————

@router.get("/branches/{branch_id}", response_model=SaleHistoryResponse)
async def list_sales(
    branch_id: str,
    status: Optional[Literal["completed", "voided", "refunded"]] = Query(None),
    payment_method: Optional[
        Literal["cash", "telebirr", "cbe_birr", "credit"]
    ] = Query(None),
    date_from: Optional[date] = Query(None, description="Local-day lower bound (inclusive)"),
    date_to: Optional[date] = Query(None, description="Local-day upper bound (inclusive)"),
    cashier_user_id: Optional[str] = Query(None),
    search: Optional[str] = Query(None, description="Sale number / customer name / phone"),
    tz: str = Query("Africa/Addis_Ababa", description="Time zone for date-range filtering"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """List/filter sales for a branch, with reconciliation totals."""
    branch = await db.fetchval("SELECT id FROM branch WHERE id = $1", branch_id)
    if not branch:
        raise HTTPException(status_code=404, detail="Branch not found.")

    pattern = f"%{search}%" if search else None
    filter_args = (
        branch_id, status, payment_method, date_from, date_to, tz,
        cashier_user_id, pattern,
    )

    # Aggregate over the FULL filtered set (ignores pagination).
    agg = await db.fetchrow(
        "SELECT COUNT(*) AS total_count, "
        "COALESCE(SUM(s.total_santim), 0) AS total_santim_sum" + _SALE_FILTER,
        *filter_args,
    )

    # Page of summaries.
    rows = await db.fetch(
        """
        SELECT s.id, s.sale_number, s.branch_id, s.cashier_user_id,
               s.dispensed_by_user_id, s.customer_name, s.customer_phone,
               s.subtotal_santim, s.vat_total_santim, s.discount_santim,
               s.total_santim, s.payment_method::text AS payment_method,
               s.payment_reference, s.sale_status::text AS sale_status,
               s.created_at
        """
        + _SALE_FILTER
        + " ORDER BY s.created_at DESC LIMIT $9 OFFSET $10",
        *filter_args, limit, offset,
    )

    sales = [
        SaleSummary(
            id=str(r["id"]),
            sale_number=r["sale_number"],
            branch_id=str(r["branch_id"]),
            cashier_user_id=str(r["cashier_user_id"]),
            dispensed_by_user_id=str(r["dispensed_by_user_id"])
            if r["dispensed_by_user_id"] else None,
            customer_name=r["customer_name"],
            customer_phone=r["customer_phone"],
            subtotal_santim=r["subtotal_santim"],
            vat_total_santim=r["vat_total_santim"],
            discount_santim=r["discount_santim"],
            total_santim=r["total_santim"],
            payment_method=r["payment_method"],
            payment_reference=r["payment_reference"],
            sale_status=r["sale_status"],
            created_at=str(r["created_at"]),
        )
        for r in rows
    ]

    return SaleHistoryResponse(
        branch_id=branch_id,
        total_count=agg["total_count"],
        total_santim_sum=agg["total_santim_sum"],
        limit=limit,
        offset=offset,
        sales=sales,
    )


# —— Detail ————————————————————————————————————————————————————————————————

@router.get("/{sale_id}", response_model=SaleDetailResponse)
async def get_sale(
    sale_id: str,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Full sale detail with line items."""
    s = await db.fetchrow(
        """
        SELECT id, sale_number, branch_id, cashier_user_id, dispensed_by_user_id,
               customer_name, customer_phone, prescription_ref,
               prescription_image_url, subtotal_santim, vat_total_santim,
               discount_santim, total_santim,
               payment_method::text AS payment_method, payment_reference,
               sale_status::text AS sale_status, void_reason, voided_by_user_id,
               created_at
        FROM sale WHERE id = $1
        """,
        sale_id,
    )
    if not s:
        raise HTTPException(status_code=404, detail="Sale not found.")

    line_rows = await db.fetch(
        """
        SELECT sl.id AS sale_line_id, sl.product_id, sl.inventory_id,
               i.batch_number, d.inn_name, p.brand_name,
               sl.quantity_sale_units, sl.quantity_base_units,
               sl.unit_price_santim, sl.line_subtotal_santim,
               sl.vat_amount_santim, sl.line_total_santim
        FROM sale_line sl
        LEFT JOIN inventory i ON i.id = sl.inventory_id
        LEFT JOIN product p   ON p.id = sl.product_id
        LEFT JOIN drug_sku ds ON ds.id = p.drug_sku_id
        LEFT JOIN drug d      ON d.id = ds.drug_id
        WHERE sl.sale_id = $1
        ORDER BY sl.id
        """,
        sale_id,
    )

    lines = [
        SaleLineDetail(
            sale_line_id=str(r["sale_line_id"]),
            product_id=str(r["product_id"]),
            inventory_id=str(r["inventory_id"]),
            batch_number=r["batch_number"],
            inn_name=r["inn_name"],
            brand_name=r["brand_name"],
            quantity_sale_units=r["quantity_sale_units"],
            quantity_base_units=r["quantity_base_units"],
            unit_price_santim=r["unit_price_santim"],
            line_subtotal_santim=r["line_subtotal_santim"],
            vat_amount_santim=r["vat_amount_santim"],
            line_total_santim=r["line_total_santim"],
        )
        for r in line_rows
    ]

    return SaleDetailResponse(
        id=str(s["id"]),
        sale_number=s["sale_number"],
        branch_id=str(s["branch_id"]),
        cashier_user_id=str(s["cashier_user_id"]),
        dispensed_by_user_id=str(s["dispensed_by_user_id"])
        if s["dispensed_by_user_id"] else None,
        customer_name=s["customer_name"],
        customer_phone=s["customer_phone"],
        prescription_ref=s["prescription_ref"],
        prescription_image_url=s["prescription_image_url"],
        subtotal_santim=s["subtotal_santim"],
        vat_total_santim=s["vat_total_santim"],
        discount_santim=s["discount_santim"],
        total_santim=s["total_santim"],
        payment_method=s["payment_method"],
        payment_reference=s["payment_reference"],
        sale_status=s["sale_status"],
        void_reason=s["void_reason"],
        voided_by_user_id=str(s["voided_by_user_id"])
        if s["voided_by_user_id"] else None,
        created_at=str(s["created_at"]),
        lines=lines,
    )
