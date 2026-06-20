"""
Supplier management endpoints.

  POST  /api/v1/suppliers                     Create supplier
  GET   /api/v1/suppliers?pharmacy_group_id=   List suppliers
  GET   /api/v1/suppliers/{supplier_id}        Get supplier
  PATCH /api/v1/suppliers/{supplier_id}        Update supplier
"""

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.auth.firebase import get_current_user
from app.database import get_db
from app.schemas.supplier import (
    SupplierCreate,
    SupplierResponse,
    SupplierUpdate,
)

router = APIRouter(prefix="/api/v1/suppliers", tags=["suppliers"])


def _supplier_response(row) -> SupplierResponse:
    return SupplierResponse(
        id=str(row["id"]),
        pharmacy_group_id=str(row["pharmacy_group_id"]),
        name=row["name"],
        supplier_type=row["supplier_type"],
        contact_person=row["contact_person"],
        phone=row["phone"],
        email=row["email"],
        tin_number=row["tin_number"],
        payment_terms_days=row["payment_terms_days"],
        currency=row["currency"].strip() if row["currency"] else "ETB",
        is_active=row["is_active"],
        created_at=str(row["created_at"]),
    )


@router.post("", response_model=SupplierResponse, status_code=status.HTTP_201_CREATED)
async def create_supplier(
    req: SupplierCreate,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Create a new supplier for a pharmacy group."""
    group = await db.fetchval(
        "SELECT id FROM pharmacy_group WHERE id = $1", req.pharmacy_group_id
    )
    if not group:
        raise HTTPException(status_code=404, detail="Pharmacy group not found.")

    row = await db.fetchrow(
        """
        INSERT INTO supplier
            (pharmacy_group_id, name, supplier_type, contact_person,
             phone, email, tin_number, payment_terms_days, currency)
        VALUES ($1, $2, $3::supplier_type, $4, $5, $6, $7, $8, $9)
        RETURNING *
        """,
        req.pharmacy_group_id, req.name, req.supplier_type,
        req.contact_person, req.phone, req.email,
        req.tin_number, req.payment_terms_days, req.currency,
    )
    return _supplier_response(row)


@router.get("", response_model=list[SupplierResponse])
async def list_suppliers(
    pharmacy_group_id: str = Query(..., description="Filter by pharmacy group"),
    active_only: bool = Query(True, description="Only active suppliers"),
    search: str = Query(None, description="Search supplier name"),
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """List suppliers for a pharmacy group."""
    conditions = ["pharmacy_group_id = $1"]
    params: list = [pharmacy_group_id]

    if active_only:
        conditions.append("is_active = true")

    if search:
        params.append(f"%{search}%")
        conditions.append(f"name ILIKE ${len(params)}")

    where = " AND ".join(conditions)
    rows = await db.fetch(
        f"SELECT * FROM supplier WHERE {where} ORDER BY name", *params
    )
    return [_supplier_response(r) for r in rows]


@router.get("/{supplier_id}", response_model=SupplierResponse)
async def get_supplier(
    supplier_id: str,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Get a single supplier."""
    row = await db.fetchrow("SELECT * FROM supplier WHERE id = $1", supplier_id)
    if not row:
        raise HTTPException(status_code=404, detail="Supplier not found.")
    return _supplier_response(row)


@router.patch("/{supplier_id}", response_model=SupplierResponse)
async def update_supplier(
    supplier_id: str,
    req: SupplierUpdate,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Update a supplier's fields."""
    existing = await db.fetchval("SELECT id FROM supplier WHERE id = $1", supplier_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Supplier not found.")

    updates = req.model_dump(exclude_none=True)
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update.")

    # Cast supplier_type to enum if present
    set_parts = []
    values = []
    for i, (col, val) in enumerate(updates.items(), start=1):
        if col == "supplier_type":
            set_parts.append(f"{col} = ${i}::supplier_type")
        else:
            set_parts.append(f"{col} = ${i}")
        values.append(val)

    values.append(supplier_id)
    idx = len(values)

    await db.execute(
        f"UPDATE supplier SET {', '.join(set_parts)} WHERE id = ${idx}", *values
    )

    row = await db.fetchrow("SELECT * FROM supplier WHERE id = $1", supplier_id)
    return _supplier_response(row)
