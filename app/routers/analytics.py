"""
Branch dashboard analytics (read-only).

  GET /api/v1/analytics/branches/{branch_id}/dashboard
        ?from_date=&to_date=&top_n=5&low_stock_threshold=10&expiring_within_days=30
      One call returning: sales summary (revenue/COGS/margin/avg basket),
      payment-method breakdown, reversal totals (voided/refunded), inventory
      valuation + low-stock/expiry counts (point-in-time), top products by
      revenue, and controlled-substance volume.

Period blocks (sales, payments, reversals, top products, controlled) filter on
the local Addis day; default range is today. Inventory blocks are
point-in-time as of the current Addis day. Revenue counts completed sales only;
voided/refunded are reported separately so they don't inflate revenue.
"""
from datetime import date

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query

from app.auth.firebase import get_current_user
from app.database import get_db
from app.schemas.analytics import (
    ControlledSummary,
    DashboardResponse,
    InventorySummary,
    PaymentBreakdown,
    ReversalSummary,
    SalesSummary,
    TopProduct,
)

router = APIRouter(prefix="/api/v1/analytics", tags=["analytics"])

_TZ = "'Africa/Addis_Ababa'"
_DAY = f"(s.created_at AT TIME ZONE {_TZ})::date"


@router.get("/branches/{branch_id}/dashboard", response_model=DashboardResponse)
async def dashboard(
    branch_id: str,
    from_date: date = Query(None, description="Local-day start (default: today)"),
    to_date: date = Query(None, description="Local-day end (default: today)"),
    top_n: int = Query(5, ge=1, le=50),
    low_stock_threshold: int = Query(None, ge=0,
                                     description="Explicit threshold; omit for per-product reorder_level"),
    expiring_within_days: int = Query(30, ge=0, le=3650),
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Single-call dashboard for a branch."""
    if not await db.fetchval("SELECT id FROM branch WHERE id = $1", branch_id):
        raise HTTPException(status_code=404, detail="Branch not found.")

    today = await db.fetchval(f"SELECT (now() AT TIME ZONE {_TZ})::date")
    f = from_date or today
    t = to_date or today

    # —— Sales header (completed) ——
    sh = await db.fetchrow(
        f"""
        SELECT COUNT(*) AS txn,
               COALESCE(SUM(s.total_santim), 0)    AS revenue,
               COALESCE(SUM(s.subtotal_santim), 0) AS subtotal,
               COALESCE(SUM(s.vat_total_santim), 0) AS vat,
               COALESCE(SUM(s.discount_santim), 0) AS discount
        FROM sale s
        WHERE s.branch_id = $1 AND s.sale_status = 'completed'
          AND {_DAY} BETWEEN $2 AND $3
        """,
        branch_id, f, t,
    )
    # COGS / margin from lines of completed sales
    sl = await db.fetchrow(
        f"""
        SELECT COALESCE(SUM(sl.cogs_santim), 0)         AS cogs,
               COALESCE(SUM(sl.gross_margin_santim), 0) AS margin
        FROM sale_line sl
        JOIN sale s ON s.id = sl.sale_id
        WHERE s.branch_id = $1 AND s.sale_status = 'completed'
          AND {_DAY} BETWEEN $2 AND $3
        """,
        branch_id, f, t,
    )
    revenue, txn, subtotal = sh["revenue"], sh["txn"], sh["subtotal"]
    sales = SalesSummary(
        txn_count=txn,
        revenue_santim=revenue,
        subtotal_santim=subtotal,
        vat_santim=sh["vat"],
        discount_santim=sh["discount"],
        cogs_santim=sl["cogs"],
        gross_margin_santim=sl["margin"],
        margin_pct=round(sl["margin"] / subtotal * 100, 2) if subtotal else 0.0,
        avg_basket_santim=revenue // txn if txn else 0,
    )

    # —— Payments (completed) ——
    pay_rows = await db.fetch(
        f"""
        SELECT s.payment_method::text AS pm, COUNT(*) AS c,
               COALESCE(SUM(s.total_santim), 0) AS rev
        FROM sale s
        WHERE s.branch_id = $1 AND s.sale_status = 'completed'
          AND {_DAY} BETWEEN $2 AND $3
        GROUP BY s.payment_method
        ORDER BY rev DESC
        """,
        branch_id, f, t,
    )
    payments = [
        PaymentBreakdown(payment_method=r["pm"], count=r["c"], revenue_santim=r["rev"])
        for r in pay_rows
    ]

    # —— Reversals ——
    rev_rows = await db.fetch(
        f"""
        SELECT s.sale_status::text AS st, COUNT(*) AS c,
               COALESCE(SUM(s.total_santim), 0) AS val
        FROM sale s
        WHERE s.branch_id = $1 AND s.sale_status IN ('voided', 'refunded')
          AND {_DAY} BETWEEN $2 AND $3
        GROUP BY s.sale_status
        """,
        branch_id, f, t,
    )
    reversals = [
        ReversalSummary(status=r["st"], count=r["c"], value_santim=r["val"])
        for r in rev_rows
    ]

    # —— Inventory valuation + expiry (point-in-time) ——
    inv = await db.fetchrow(
        """
        SELECT
          COUNT(DISTINCT i.product_id) FILTER (WHERE i.expiry_date >= $2) AS distinct_products,
          COALESCE(SUM(i.quantity_base_units * i.cost_per_base_unit_santim)
                   FILTER (WHERE i.expiry_date >= $2), 0) AS cost_value,
          COALESCE(ROUND(SUM(
                   (i.quantity_base_units::numeric / NULLIF(p.sale_unit_size, 0))
                   * i.selling_price_per_sale_unit_santim)
                   FILTER (WHERE i.expiry_date >= $2)), 0)::bigint AS retail_value,
          COUNT(*) FILTER (WHERE i.expiry_date < $2) AS expired_lots,
          COALESCE(SUM(i.quantity_base_units * i.cost_per_base_unit_santim)
                   FILTER (WHERE i.expiry_date < $2), 0) AS expired_cost,
          COUNT(*) FILTER (WHERE i.expiry_date >= $2
                             AND i.expiry_date <= $2 + $3::int) AS expiring_soon
        FROM inventory i
        JOIN product p ON p.id = i.product_id
        WHERE i.branch_id = $1 AND i.is_active = true AND i.quantity_base_units > 0
        """,
        branch_id, today, expiring_within_days,
    )
    low_stock_count = await db.fetchval(
        """
        SELECT COUNT(*) FROM (
          SELECT p.id, p.reorder_level,
                 COALESCE(SUM(i.quantity_base_units) FILTER (
                     WHERE i.is_active AND i.quantity_base_units > 0
                       AND i.expiry_date >= $2), 0) AS avail
          FROM inventory i
          JOIN product p ON p.id = i.product_id
          WHERE i.branch_id = $1
          GROUP BY p.id, p.reorder_level
          HAVING COALESCE(SUM(i.quantity_base_units) FILTER (
                     WHERE i.is_active AND i.quantity_base_units > 0
                       AND i.expiry_date >= $2), 0) < COALESCE($3::int, p.reorder_level)
        ) x
        """,
        branch_id, today, low_stock_threshold,
    )
    inventory = InventorySummary(
        distinct_products_in_stock=inv["distinct_products"],
        stock_cost_santim=inv["cost_value"],
        stock_retail_santim=inv["retail_value"],
        low_stock_count=low_stock_count,
        low_stock_threshold=low_stock_threshold,
        expiring_soon_count=inv["expiring_soon"],
        expiring_within_days=expiring_within_days,
        expired_lot_count=inv["expired_lots"],
        expired_cost_santim=inv["expired_cost"],
    )

    # —— Top products (completed) — two leaderboards: revenue & quantity ——
    _TOP_SQL = f"""
        SELECT p.id AS pid, d.inn_name, p.brand_name,
               COALESCE(SUM(sl.line_total_santim), 0)   AS rev,
               COALESCE(SUM(sl.quantity_base_units), 0) AS qty,
               COALESCE(SUM(sl.gross_margin_santim), 0) AS margin
        FROM sale_line sl
        JOIN sale s      ON s.id = sl.sale_id
        JOIN product p   ON p.id = sl.product_id
        JOIN drug_sku ds ON ds.id = p.drug_sku_id
        JOIN drug d      ON d.id = ds.drug_id
        WHERE s.branch_id = $1 AND s.sale_status = 'completed'
          AND {_DAY} BETWEEN $2 AND $3
        GROUP BY p.id, d.inn_name, p.brand_name
        ORDER BY {{order_col}} DESC
        LIMIT $4
    """

    def _top(rows):
        return [
            TopProduct(
                product_id=str(r["pid"]),
                inn_name=r["inn_name"],
                brand_name=r["brand_name"],
                revenue_santim=r["rev"],
                quantity_base_units=r["qty"],
                gross_margin_santim=r["margin"],
            )
            for r in rows
        ]

    top_by_revenue = _top(
        await db.fetch(_TOP_SQL.format(order_col="rev"), branch_id, f, t, top_n)
    )
    top_by_quantity = _top(
        await db.fetch(_TOP_SQL.format(order_col="qty"), branch_id, f, t, top_n)
    )

    # —— Controlled-substance volume ——
    ctrl = await db.fetchrow(
        f"""
        SELECT COUNT(*) AS c,
               COALESCE(SUM(nr.dispensed_quantity_base_units), 0) AS vol
        FROM narcotics_register nr
        WHERE nr.branch_id = $1
          AND (nr.dispensed_at AT TIME ZONE {_TZ})::date BETWEEN $2 AND $3
        """,
        branch_id, f, t,
    )
    controlled = ControlledSummary(dispense_count=ctrl["c"], volume_base_units=ctrl["vol"])

    return DashboardResponse(
        branch_id=branch_id,
        from_date=str(f),
        to_date=str(t),
        as_of_date=str(today),
        sales=sales,
        payments=payments,
        reversals=reversals,
        inventory=inventory,
        top_products_by_revenue=top_by_revenue,
        top_products_by_quantity=top_by_quantity,
        controlled=controlled,
    )
