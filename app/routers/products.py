"""
Product management endpoints — CRUD and barcode lookup.

  POST /api/v1/products
      Create a product (link a drug_sku to a pharmacy group).

  GET  /api/v1/products?pharmacy_group_id=...&search=...
      List products for a pharmacy group, with optional text search
      across drug name, brand name, and barcode.

  GET  /api/v1/products/{product_id}
      Get product detail with joined catalog info.

  PATCH /api/v1/products/{product_id}
      Update mutable product fields.

  GET  /api/v1/products/lookup?barcode=...&branch_id=...
      Barcode scan — searches primary_barcode and secondary_barcodes.
      Optionally returns branch stock count.
"""

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.auth.firebase import get_current_user
from app.database import get_db
from app.schemas.product import (
    BarcodeLookupResponse,
    ProductCreate,
    ProductResponse,
    ProductUpdate,
)

router = APIRouter(prefix="/api/v1/products", tags=["products"])

# Shared SELECT for consistent response shape
_PRODUCT_SELECT = """
    SELECT p.id, p.drug_sku_id, p.pharmacy_group_id, p.brand_name,
           p.pack_size, p.sale_unit, p.sale_unit_size,
           p.primary_barcode, p.secondary_barcodes,
           p.image_url, p.country_of_origin, p.supplier_id, p.created_at,
           d.inn_name, ds.dosage_form::text, ds.strength
    FROM product p
    JOIN drug_sku ds ON ds.id = p.drug_sku_id
    JOIN drug d ON d.id = ds.drug_id
"""


def _product_response(row) -> ProductResponse:
    return ProductResponse(
        id=str(row["id"]),
        drug_sku_id=str(row["drug_sku_id"]),
        pharmacy_group_id=str(row["pharmacy_group_id"]) if row["pharmacy_group_id"] else None,
        brand_name=row["brand_name"],
        pack_size=row["pack_size"],
        sale_unit=row["sale_unit"],
        sale_unit_size=row["sale_unit_size"],
        primary_barcode=row["primary_barcode"],
        secondary_barcodes=row["secondary_barcodes"],
        image_url=row["image_url"],
        country_of_origin=row["country_of_origin"].strip() if row["country_of_origin"] else None,
        supplier_id=str(row["supplier_id"]) if row["supplier_id"] else None,
        created_at=str(row["created_at"]),
        inn_name=row["inn_name"],
        dosage_form=row["dosage_form"],
        strength=row["strength"],
    )


# —— Create ———————————————————————————————————————————————————————————

@router.post("", response_model=ProductResponse, status_code=status.HTTP_201_CREATED)
async def create_product(
    req: ProductCreate,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Create a product linking a catalog drug_sku to a pharmacy group."""
    # Verify drug_sku exists
    sku = await db.fetchval("SELECT id FROM drug_sku WHERE id = $1", req.drug_sku_id)
    if not sku:
        raise HTTPException(status_code=404, detail="Drug SKU not found.")

    # Verify pharmacy group exists
    group = await db.fetchval(
        "SELECT id FROM pharmacy_group WHERE id = $1", req.pharmacy_group_id
    )
    if not group:
        raise HTTPException(status_code=404, detail="Pharmacy group not found.")

    try:
        await db.execute(
            """
            INSERT INTO product
                (drug_sku_id, pharmacy_group_id, brand_name, pack_size,
                 sale_unit, sale_unit_size, primary_barcode, secondary_barcodes,
                 image_url, country_of_origin, supplier_id)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
            """,
            req.drug_sku_id, req.pharmacy_group_id, req.brand_name,
            req.pack_size, req.sale_unit, req.sale_unit_size,
            req.primary_barcode, req.secondary_barcodes,
            req.image_url, req.country_of_origin, req.supplier_id,
        )
    except asyncpg.UniqueViolationError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A product with that barcode already exists.",
        )

    # Fetch back with joined catalog data
    row = await db.fetchrow(
        _PRODUCT_SELECT + " WHERE p.drug_sku_id = $1 AND p.pharmacy_group_id = $2 "
        "ORDER BY p.created_at DESC LIMIT 1",
        req.drug_sku_id, req.pharmacy_group_id,
    )
    return _product_response(row)


# —— List / Search ————————————————————————————————————————————————————

@router.get("", response_model=list[ProductResponse])
async def list_products(
    pharmacy_group_id: str = Query(..., description="Filter by pharmacy group"),
    search: str = Query(None, description="Search drug name, brand, or barcode"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """List products for a pharmacy group, with optional text search."""
    if search:
        pattern = f"%{search}%"
        rows = await db.fetch(
            _PRODUCT_SELECT
            + """
            WHERE p.pharmacy_group_id = $1
              AND (d.inn_name ILIKE $2
                   OR p.brand_name ILIKE $2
                   OR p.primary_barcode ILIKE $2)
            ORDER BY d.inn_name
            LIMIT $3 OFFSET $4
            """,
            pharmacy_group_id, pattern, limit, offset,
        )
    else:
        rows = await db.fetch(
            _PRODUCT_SELECT
            + """
            WHERE p.pharmacy_group_id = $1
            ORDER BY d.inn_name
            LIMIT $2 OFFSET $3
            """,
            pharmacy_group_id, limit, offset,
        )
    return [_product_response(r) for r in rows]


# —— Barcode lookup (must be above /{product_id} to avoid route clash) ——

@router.get("/lookup", response_model=BarcodeLookupResponse)
async def barcode_lookup(
    barcode: str = Query(..., description="Barcode to scan"),
    branch_id: str = Query(None, description="Optional branch for stock count"),
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """
    Look up a product by barcode (primary or secondary).
    Optionally returns available stock at a specific branch.
    """
    row = await db.fetchrow(
        _PRODUCT_SELECT
        + " WHERE p.primary_barcode = $1 OR $1 = ANY(p.secondary_barcodes)",
        barcode,
    )
    if not row:
        raise HTTPException(status_code=404, detail="No product found for this barcode.")

    product = _product_response(row)
    stock = None

    if branch_id:
        stock = await db.fetchval(
            """
            SELECT COALESCE(SUM(quantity_base_units), 0)
            FROM inventory
            WHERE branch_id = $1 AND product_id = $2
              AND is_active = true AND expiry_date >= CURRENT_DATE
              AND quantity_base_units > 0
            """,
            branch_id, row["id"],
        )

    return BarcodeLookupResponse(product=product, branch_stock=stock)


# —— Detail ———————————————————————————————————————————————————————————

@router.get("/{product_id}", response_model=ProductResponse)
async def get_product(
    product_id: str,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Get a single product with joined catalog info."""
    row = await db.fetchrow(_PRODUCT_SELECT + " WHERE p.id = $1", product_id)
    if not row:
        raise HTTPException(status_code=404, detail="Product not found.")
    return _product_response(row)


# —— Update (PATCH) ———————————————————————————————————————————————————

@router.patch("/{product_id}", response_model=ProductResponse)
async def update_product(
    product_id: str,
    req: ProductUpdate,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Update mutable fields on a product."""
    # Verify product exists
    existing = await db.fetchval("SELECT id FROM product WHERE id = $1", product_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Product not found.")

    # Build dynamic SET clause from non-None fields
    updates = req.model_dump(exclude_none=True)
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update.")

    set_parts = []
    values = []
    for i, (col, val) in enumerate(updates.items(), start=1):
        set_parts.append(f"{col} = ${i}")
        values.append(val)

    values.append(product_id)
    idx = len(values)

    try:
        await db.execute(
            f"UPDATE product SET {', '.join(set_parts)} WHERE id = ${idx}",
            *values,
        )
    except asyncpg.UniqueViolationError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A product with that barcode already exists.",
        )

    row = await db.fetchrow(_PRODUCT_SELECT + " WHERE p.id = $1", product_id)
    return _product_response(row)
