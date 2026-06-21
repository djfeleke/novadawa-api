"""
Narcotics register — report & CSV export (read-only, EFDA audit artifact).

  GET /api/v1/narcotics/branches/{branch_id}/register
        ?from_date=&to_date=&drug_sku_id=&drug_search=&patient_search=
      Filterable JSON list of controlled-substance dispenses, newest first,
      with total_count and total_dispensed_base_units over the filtered set.

  GET /api/v1/narcotics/branches/{branch_id}/register/export.csv
        (same filters)
      Downloadable CSV in conventional controlled-substance-register column
      order, for hand-off to EFDA inspectors.

Read-only: never mutates the register. Date filtering uses the local Addis
day on dispensed_at. dispensed_at is rendered in local Addis time.
"""
import csv
import io
from datetime import date

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, Response

from app.auth.firebase import get_current_user
from app.database import get_db
from app.schemas.narcotics import (
    NarcoticsRegisterEntry,
    NarcoticsRegisterResponse,
)

router = APIRouter(prefix="/api/v1/narcotics", tags=["narcotics"])

# Shared FROM + WHERE for list / aggregate / export (params $1..$6).
#   $1 branch_id  $2 from_date  $3 to_date
#   $4 drug_sku_id  $5 drug_search pattern  $6 patient_search pattern
_FROM = """
    FROM narcotics_register nr
    JOIN sale_line sl ON sl.id = nr.sale_line_id
    JOIN sale s       ON s.id = sl.sale_id
    JOIN drug_sku ds  ON ds.id = nr.drug_sku_id
    JOIN drug d       ON d.id = ds.drug_id
    LEFT JOIN app_user u ON u.id = nr.dispensed_by_user_id
    WHERE nr.branch_id = $1
      AND ($2::date IS NULL OR (nr.dispensed_at AT TIME ZONE 'Africa/Addis_Ababa')::date >= $2)
      AND ($3::date IS NULL OR (nr.dispensed_at AT TIME ZONE 'Africa/Addis_Ababa')::date <= $3)
      AND ($4::uuid IS NULL OR nr.drug_sku_id = $4)
      AND ($5::text IS NULL OR d.inn_name ILIKE $5)
      AND ($6::text IS NULL
           OR nr.patient_full_name ILIKE $6
           OR nr.patient_id_number ILIKE $6)
"""

_COLS = """
    SELECT nr.id,
           to_char((nr.dispensed_at AT TIME ZONE 'Africa/Addis_Ababa'),
                   'YYYY-MM-DD HH24:MI') AS dispensed_at,
           sl.id AS sale_line_id, sl.sale_id, s.sale_number,
           nr.drug_sku_id, d.inn_name, ds.narcotic_class,
           nr.dispensed_quantity_base_units, nr.running_balance_base_units,
           nr.patient_full_name, nr.patient_id_type, nr.patient_id_number,
           nr.prescribing_doctor_name, nr.prescribing_doctor_license,
           nr.prescription_serial, nr.prescription_image_url,
           nr.dispensed_by_user_id,
           u.full_name AS dispensed_by_name,
           u.efda_license_number AS dispensed_by_license
"""


def _entry(r) -> NarcoticsRegisterEntry:
    return NarcoticsRegisterEntry(
        id=str(r["id"]),
        dispensed_at=r["dispensed_at"],
        sale_line_id=str(r["sale_line_id"]),
        sale_id=str(r["sale_id"]),
        sale_number=r["sale_number"],
        drug_sku_id=str(r["drug_sku_id"]),
        inn_name=r["inn_name"],
        narcotic_class=r["narcotic_class"],
        dispensed_quantity_base_units=r["dispensed_quantity_base_units"],
        running_balance_base_units=r["running_balance_base_units"],
        patient_full_name=r["patient_full_name"],
        patient_id_type=r["patient_id_type"],
        patient_id_number=r["patient_id_number"],
        prescribing_doctor_name=r["prescribing_doctor_name"],
        prescribing_doctor_license=r["prescribing_doctor_license"],
        prescription_serial=r["prescription_serial"],
        prescription_image_url=r["prescription_image_url"],
        dispensed_by_user_id=str(r["dispensed_by_user_id"]),
        dispensed_by_name=r["dispensed_by_name"],
        dispensed_by_license=r["dispensed_by_license"],
    )


async def _check_branch(db, branch_id):
    if not await db.fetchval("SELECT id FROM branch WHERE id = $1", branch_id):
        raise HTTPException(status_code=404, detail="Branch not found.")


# —— JSON report ———————————————————————————————————————————————————————————

@router.get("/branches/{branch_id}/register", response_model=NarcoticsRegisterResponse)
async def register_report(
    branch_id: str,
    from_date: date = Query(None, description="Local-day lower bound YYYY-MM-DD"),
    to_date: date = Query(None, description="Local-day upper bound YYYY-MM-DD"),
    drug_sku_id: str = Query(None),
    drug_search: str = Query(None, description="Drug INN name contains"),
    patient_search: str = Query(None, description="Patient name or ID number contains"),
    limit: int = Query(100, ge=1, le=1000),
    offset: int = Query(0, ge=0),
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Filterable narcotics register for a branch, with audit totals."""
    await _check_branch(db, branch_id)

    drug_pat = f"%{drug_search}%" if drug_search else None
    pat_pat = f"%{patient_search}%" if patient_search else None
    args = (branch_id, from_date, to_date, drug_sku_id, drug_pat, pat_pat)

    agg = await db.fetchrow(
        "SELECT COUNT(*) AS total_count, "
        "COALESCE(SUM(nr.dispensed_quantity_base_units), 0) AS total_dispensed"
        + _FROM,
        *args,
    )
    rows = await db.fetch(
        _COLS + _FROM + " ORDER BY nr.dispensed_at DESC LIMIT $7 OFFSET $8",
        *args, limit, offset,
    )

    return NarcoticsRegisterResponse(
        branch_id=branch_id,
        from_date=str(from_date) if from_date else None,
        to_date=str(to_date) if to_date else None,
        total_count=agg["total_count"],
        total_dispensed_base_units=agg["total_dispensed"],
        limit=limit,
        offset=offset,
        entries=[_entry(r) for r in rows],
    )


# —— CSV export ————————————————————————————————————————————————————————————

_CSV_HEADER = [
    "Dispensed At", "Drug (INN)", "Narcotic Class", "Sale Number",
    "Quantity (base units)", "Running Balance (base units)",
    "Patient Name", "Patient ID Type", "Patient ID Number",
    "Prescriber Name", "Prescriber License", "Rx Serial",
    "Dispenser Name", "Dispenser License",
]


@router.get("/branches/{branch_id}/register/export.csv")
async def register_export_csv(
    branch_id: str,
    from_date: date = Query(None),
    to_date: date = Query(None),
    drug_sku_id: str = Query(None),
    drug_search: str = Query(None),
    patient_search: str = Query(None),
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Download the filtered narcotics register as CSV (EFDA hand-off)."""
    await _check_branch(db, branch_id)

    drug_pat = f"%{drug_search}%" if drug_search else None
    pat_pat = f"%{patient_search}%" if patient_search else None
    args = (branch_id, from_date, to_date, drug_sku_id, drug_pat, pat_pat)

    rows = await db.fetch(_COLS + _FROM + " ORDER BY nr.dispensed_at ASC", *args)

    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(_CSV_HEADER)
    for r in rows:
        w.writerow([
            r["dispensed_at"], r["inn_name"], r["narcotic_class"], r["sale_number"],
            r["dispensed_quantity_base_units"], r["running_balance_base_units"],
            r["patient_full_name"], r["patient_id_type"], r["patient_id_number"],
            r["prescribing_doctor_name"], r["prescribing_doctor_license"],
            r["prescription_serial"], r["dispensed_by_name"], r["dispensed_by_license"],
        ])

    filename = f"narcotics_register_{branch_id}.csv"
    return Response(
        content=buf.getvalue(),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# —— PDF export ————————————————————————————————————————————————————————————

@router.get("/branches/{branch_id}/register/export.pdf")
async def register_export_pdf(
    branch_id: str,
    from_date: date = Query(None),
    to_date: date = Query(None),
    drug_sku_id: str = Query(None),
    drug_search: str = Query(None),
    patient_search: str = Query(None),
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Download the filtered narcotics register as a formatted PDF (EFDA hand-off)."""
    # Lazy import so the app still boots if reportlab isn't installed.
    try:
        from reportlab.lib import colors
        from reportlab.lib.pagesizes import A4, landscape
        from reportlab.lib.styles import ParagraphStyle
        from reportlab.lib.units import mm
        from reportlab.platypus import (
            Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle,
        )
    except ImportError:
        raise HTTPException(
            status_code=501,
            detail="PDF export requires reportlab. Install it with: pip install reportlab",
        )

    branch = await db.fetchrow(
        "SELECT name, woreda, city FROM branch WHERE id = $1", branch_id
    )
    if not branch:
        raise HTTPException(status_code=404, detail="Branch not found.")

    drug_pat = f"%{drug_search}%" if drug_search else None
    pat_pat = f"%{patient_search}%" if patient_search else None
    args = (branch_id, from_date, to_date, drug_sku_id, drug_pat, pat_pat)
    rows = await db.fetch(_COLS + _FROM + " ORDER BY nr.dispensed_at ASC", *args)

    cell = ParagraphStyle("cell", fontName="Helvetica", fontSize=6.5, leading=8)
    head = ParagraphStyle("head", fontName="Helvetica-Bold", fontSize=6.5, leading=8,
                           textColor=colors.white)
    title_s = ParagraphStyle("title", fontName="Helvetica-Bold", fontSize=13, leading=16)
    sub_s = ParagraphStyle("sub", fontName="Helvetica", fontSize=8, leading=11)

    def P(text, style=cell):
        return Paragraph("" if text is None else str(text).replace("&", "&amp;"), style)

    headers = ["Dispensed", "Drug (INN)", "Class", "Qty", "Bal.", "Patient",
               "ID Type", "ID No.", "Prescriber", "Lic.", "Rx Serial", "Dispenser"]
    data = [[P(h, head) for h in headers]]
    for r in rows:
        data.append([
            P(r["dispensed_at"]), P(r["inn_name"]), P(r["narcotic_class"]),
            P(r["dispensed_quantity_base_units"]), P(r["running_balance_base_units"]),
            P(r["patient_full_name"]), P(r["patient_id_type"]), P(r["patient_id_number"]),
            P(r["prescribing_doctor_name"]), P(r["prescribing_doctor_license"]),
            P(r["prescription_serial"]), P(r["dispensed_by_name"]),
        ])

    col_widths = [26, 34, 18, 10, 12, 30, 20, 24, 30, 18, 24, 28]
    col_widths = [w * mm for w in col_widths]

    table = Table(data, colWidths=col_widths, repeatRows=1)
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1f4e5f")),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#999999")),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f2f6f7")]),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 2),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
        ("LEFTPADDING", (0, 0), (-1, -1), 3),
        ("RIGHTPADDING", (0, 0), (-1, -1), 3),
    ]))

    period = ""
    if from_date or to_date:
        period = f" — {from_date or '...'} to {to_date or '...'}"
    loc = ", ".join(x for x in [branch["woreda"], branch["city"]] if x)

    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf, pagesize=landscape(A4),
        leftMargin=10 * mm, rightMargin=10 * mm,
        topMargin=10 * mm, bottomMargin=10 * mm,
        title="Narcotics Register",
    )
    story = [
        Paragraph("Controlled Substances Register", title_s),
        Paragraph(f"{branch['name']} ({loc}){period}", sub_s),
        Paragraph(f"{len(rows)} dispense record(s)", sub_s),
        Spacer(1, 6 * mm),
        table,
    ]
    doc.build(story)

    filename = f"narcotics_register_{branch_id}.pdf"
    return Response(
        content=buf.getvalue(),
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
