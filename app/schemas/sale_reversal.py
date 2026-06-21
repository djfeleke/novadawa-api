"""Pydantic models for sale void / refund (reversal)."""
from typing import Optional
from pydantic import BaseModel, Field


# ---------- Request ----------
class SaleReversalRequest(BaseModel):
    reason: str = Field(..., min_length=1, description="Why the sale is being reversed.")
    performed_by_user_id: str
    restock: bool = Field(
        True,
        description="Return stock to its original lot. Set false for damaged/unsellable "
                    "goods. Must be true when the sale contains a controlled substance.",
    )


# ---------- Response ----------
class ReversedLine(BaseModel):
    sale_line_id: str
    inventory_id: str
    product_id: str
    restored_base_units: int                      # 0 when restock=false
    inventory_after_base_units: Optional[int] = None  # null when restock=false


class SaleReversalResponse(BaseModel):
    sale_id: str
    sale_number: str
    sale_status: str                  # voided | refunded
    restocked: bool
    lines_reversed: int
    total_restored_base_units: int
    narcotics_reversed_count: int = 0  # controlled-substance reversal records written
    reason: str
    performed_by_user_id: str
    lines: list[ReversedLine]
