"""Pydantic models for branch dashboard analytics (read-only)."""
from typing import Optional
from pydantic import BaseModel


class SalesSummary(BaseModel):
    txn_count: int
    revenue_santim: int               # SUM(total_santim) of completed sales (incl VAT)
    subtotal_santim: int              # pre-VAT
    vat_santim: int
    discount_santim: int
    cogs_santim: int
    gross_margin_santim: int          # pre-VAT margin (subtotal - cogs)
    margin_pct: float                 # gross_margin / subtotal * 100
    avg_basket_santim: int            # revenue / txn_count


class PaymentBreakdown(BaseModel):
    payment_method: str
    count: int
    revenue_santim: int


class ReversalSummary(BaseModel):
    status: str                       # voided | refunded
    count: int
    value_santim: int


class InventorySummary(BaseModel):
    distinct_products_in_stock: int
    stock_cost_santim: int            # non-expired, at cost
    stock_retail_santim: int          # non-expired, at retail
    low_stock_count: int
    low_stock_threshold: Optional[int]  # explicit param, or null = per-product reorder_level
    expiring_soon_count: int
    expiring_within_days: int
    expired_lot_count: int
    expired_cost_santim: int


class TopProduct(BaseModel):
    product_id: str
    inn_name: Optional[str]
    brand_name: Optional[str]
    revenue_santim: int
    quantity_base_units: int
    gross_margin_santim: int


class ControlledSummary(BaseModel):
    dispense_count: int
    volume_base_units: int


class DashboardResponse(BaseModel):
    branch_id: str
    from_date: str
    to_date: str
    as_of_date: str                   # local Addis date for point-in-time blocks
    sales: SalesSummary
    payments: list[PaymentBreakdown]
    reversals: list[ReversalSummary]
    inventory: InventorySummary
    top_products_by_revenue: list[TopProduct]    # high-value / high-margin movers
    top_products_by_quantity: list[TopProduct]   # high-turnover items
    controlled: ControlledSummary
