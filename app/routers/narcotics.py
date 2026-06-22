"""
Narcotics register — report & exports (read-only, EFDA audit artifact).

  GET /api/v1/narcotics/branches/{branch_id}/register
        ?from_date=&to_date=&drug_sku_id=&drug_search=&patient_search=&class=
      Filterable JSON list of controlled-substance dispenses, newest first,
      with total_count and total_dispensed_base_units over the filtered set.
      Richer internal columns (age/sex/address, dispenser, balance, override).

  GET /api/v1/narcotics/branches/{branch_id}/register/export.csv
        (same filters, incl. optional class=)
      Downloadable richer CSV for internal review / audit prep.

  GET /api/v1/narcotics/branches/{branch_id}/register/export.pdf?class=...
      Official EFDA dispensing register PDF. class is REQUIRED:
        narcotic     -> FORM NPS/09/A
        psychotropic -> FORM NPS/09/B
      Columns match the official form exactly.

The optional `class` filter (narcotic | psychotropic) on the JSON/CSV slices the
register by drug_sku.narcotic_class; omit it for all controlled dispenses.

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

# Shared FROM + WHERE for list / aggregate / export (params $1..$7).
#   $1 branch_id  $2 from_date  $3 to_date
#   $4 drug_sku_id  $5 drug_search pattern  $6 patient_search pattern
#   $7 class ('narcotic' | 'psychotropic' | NULL = all)
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
      AND ($7::text IS NULL OR ds.narcotic_class = $7)
"""

_COLS = """
    SELECT nr.id,
           to_char((nr.dispensed_at AT TIME ZONE 'Africa/Addis_Ababa'),
                   'YYYY-MM-DD HH24:MI') AS dispensed_at,
           sl.id AS sale_line_id, sl.sale_id, s.sale_number,
           nr.drug_sku_id, d.inn_name, ds.narcotic_class,
           ds.strength, ds.dosage_form,
           nr.dispensed_quantity_base_units, nr.running_balance_base_units,
           nr.patient_full_name, nr.patient_age, nr.patient_sex,
           nr.patient_address,
           nr.patient_id_type, nr.patient_id_number,
           nr.prescribing_doctor_name, nr.prescribing_doctor_license,
           nr.prescription_serial, nr.prescription_image_url,
           nr.override_reason, nr.overridden_by_user_id,
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
        strength=r["strength"],
        dosage_form=r["dosage_form"],
        dispensed_quantity_base_units=r["dispensed_quantity_base_units"],
        running_balance_base_units=r["running_balance_base_units"],
        patient_full_name=r["patient_full_name"],
        patient_age=r["patient_age"],
        patient_sex=r["patient_sex"],
        patient_address=r["patient_address"],
        patient_id_type=r["patient_id_type"],
        patient_id_number=r["patient_id_number"],
        prescribing_doctor_name=r["prescribing_doctor_name"],
        prescribing_doctor_license=r["prescribing_doctor_license"],
        prescription_serial=r["prescription_serial"],
        prescription_image_url=r["prescription_image_url"],
        override_reason=r["override_reason"],
        overridden_by_user_id=(
            str(r["overridden_by_user_id"]) if r["overridden_by_user_id"] else None
        ),
        dispensed_by_user_id=str(r["dispensed_by_user_id"]),
        dispensed_by_name=r["dispensed_by_name"],
        dispensed_by_license=r["dispensed_by_license"],
    )


async def _check_branch(db, branch_id):
    if not await db.fetchval("SELECT id FROM branch WHERE id = $1", branch_id):
        raise HTTPException(status_code=404, detail="Branch not found.")


_VALID_CLASSES = {"narcotic", "psychotropic"}


def _validate_class(value, *, required=False):
    """Normalise/validate the class filter. Returns None for 'all'."""
    if value is None or (isinstance(value, str) and not value.strip()):
        if required:
            raise HTTPException(
                status_code=400,
                detail="class is required and must be 'narcotic' or 'psychotropic'.",
            )
        return None
    v = value.strip().lower()
    if v not in _VALID_CLASSES:
        raise HTTPException(
            status_code=400,
            detail="class must be 'narcotic' or 'psychotropic'.",
        )
    return v


# —— JSON report ———————————————————————————————————————————————————————————

@router.get("/branches/{branch_id}/register", response_model=NarcoticsRegisterResponse)
async def register_report(
    branch_id: str,
    from_date: date = Query(None, description="Local-day lower bound YYYY-MM-DD"),
    to_date: date = Query(None, description="Local-day upper bound YYYY-MM-DD"),
    drug_sku_id: str = Query(None),
    drug_search: str = Query(None, description="Drug INN name contains"),
    patient_search: str = Query(None, description="Patient name or ID number contains"),
    narcotic_class: str = Query(
        None,
        alias="class",
        description="Filter by class: 'narcotic' | 'psychotropic' (omit for all)",
    ),
    limit: int = Query(100, ge=1, le=1000),
    offset: int = Query(0, ge=0),
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Filterable narcotics register for a branch, with audit totals."""
    await _check_branch(db, branch_id)
    klass = _validate_class(narcotic_class)

    drug_pat = f"%{drug_search}%" if drug_search else None
    pat_pat = f"%{patient_search}%" if patient_search else None
    args = (branch_id, from_date, to_date, drug_sku_id, drug_pat, pat_pat, klass)

    agg = await db.fetchrow(
        "SELECT COUNT(*) AS total_count, "
        "COALESCE(SUM(nr.dispensed_quantity_base_units), 0) AS total_dispensed"
        + _FROM,
        *args,
    )
    rows = await db.fetch(
        _COLS + _FROM + " ORDER BY nr.dispensed_at DESC LIMIT $8 OFFSET $9",
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
    "Dispensed At", "Drug (INN)", "Strength", "Narcotic Class", "Sale Number",
    "Quantity", "Unit", "Running Balance",
    "Patient Name", "Patient Age", "Patient Sex", "Patient Address",
    "Patient ID Type", "Patient ID Number",
    "Prescriber Name", "Prescriber License", "Rx Serial",
    "Dispenser Name", "Dispenser License",
    "Override Reason",
]


@router.get("/branches/{branch_id}/register/export.csv")
async def register_export_csv(
    branch_id: str,
    from_date: date = Query(None),
    to_date: date = Query(None),
    drug_sku_id: str = Query(None),
    drug_search: str = Query(None),
    patient_search: str = Query(None),
    narcotic_class: str = Query(None, alias="class"),
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Download the filtered narcotics register as CSV (EFDA hand-off)."""
    await _check_branch(db, branch_id)
    klass = _validate_class(narcotic_class)

    drug_pat = f"%{drug_search}%" if drug_search else None
    pat_pat = f"%{patient_search}%" if patient_search else None
    args = (branch_id, from_date, to_date, drug_sku_id, drug_pat, pat_pat, klass)

    rows = await db.fetch(_COLS + _FROM + " ORDER BY nr.dispensed_at ASC", *args)

    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(_CSV_HEADER)
    for r in rows:
        w.writerow([
            r["dispensed_at"], r["inn_name"], r["strength"], r["narcotic_class"],
            r["sale_number"],
            r["dispensed_quantity_base_units"], r["dosage_form"],
            r["running_balance_base_units"],
            r["patient_full_name"], r["patient_age"], r["patient_sex"],
            r["patient_address"],
            r["patient_id_type"], r["patient_id_number"],
            r["prescribing_doctor_name"], r["prescribing_doctor_license"],
            r["prescription_serial"], r["dispensed_by_name"], r["dispensed_by_license"],
            r["override_reason"],
        ])

    filename = f"narcotics_register_{branch_id}.csv"
    return Response(
        content=buf.getvalue(),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# —— PDF export ————————————————————————————————————————————————————————————

# Official EFDA dispensing-register forms (identical columns, differ by class).
_FORM_META = {
    "narcotic": {
        "form_no": "FORM NPS/09/A",
        "title": "Record of Dispensed Narcotic Drugs in Dispensary Pharmacy",
    },
    "psychotropic": {
        "form_no": "FORM NPS/09/B",
        "title": "Record of Dispensed Psychotropic Drugs in Dispensary Pharmacy",
    },
}


@router.get("/branches/{branch_id}/register/export.pdf")
async def register_export_pdf(
    branch_id: str,
    narcotic_class: str = Query(
        ...,
        alias="class",
        description="Required: 'narcotic' (NPS/09/A) or 'psychotropic' (NPS/09/B)",
    ),
    from_date: date = Query(None),
    to_date: date = Query(None),
    drug_sku_id: str = Query(None),
    drug_search: str = Query(None),
    patient_search: str = Query(None),
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """
    Download the official EFDA dispensing register as a PDF.

    class=narcotic     -> FORM NPS/09/A (Narcotic Drugs)
    class=psychotropic -> FORM NPS/09/B (Psychotropic Drugs)

    Columns match the official form exactly: S.No, Date, Name of patient, Age,
    Sex, Address, Description of drug, Quantity dispensed, Name of prescriber,
    Prescription serial No.
    """
    # class is required for an official form (one PDF = one official document).
    klass = _validate_class(narcotic_class, required=True)
    meta = _FORM_META[klass]

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
        "SELECT name, woreda, city, efda_branch_license FROM branch WHERE id = $1",
        branch_id,
    )
    if not branch:
        raise HTTPException(status_code=404, detail="Branch not found.")

    drug_pat = f"%{drug_search}%" if drug_search else None
    pat_pat = f"%{patient_search}%" if patient_search else None
    args = (branch_id, from_date, to_date, drug_sku_id, drug_pat, pat_pat, klass)
    rows = await db.fetch(_COLS + _FROM + " ORDER BY nr.dispensed_at ASC", *args)

    cell = ParagraphStyle("cell", fontName="Helvetica", fontSize=7, leading=9)
    head = ParagraphStyle("head", fontName="Helvetica-Bold", fontSize=7, leading=9,
                           textColor=colors.white)
    form_s = ParagraphStyle("form", fontName="Helvetica-Bold", fontSize=9, leading=12,
                            alignment=2)  # right
    title_s = ParagraphStyle("title", fontName="Helvetica-Bold", fontSize=13, leading=16)
    sub_s = ParagraphStyle("sub", fontName="Helvetica", fontSize=8, leading=12)

    def P(text, style=cell):
        return Paragraph("" if text is None else str(text).replace("&", "&amp;"), style)

    # Official NPS/09 column set, in the form's exact order.
    headers = ["S.No", "Date", "Name of patient", "Age", "Sex", "Address",
               "Description of drug", "Quantity dispensed",
               "Name of prescriber", "Prescription serial No"]
    data = [[P(h, head) for h in headers]]
    for i, r in enumerate(rows, 1):
        # "Description of drug" = INN + strength + dosage form (e.g. the unit).
        desc = r["inn_name"] or ""
        if r["strength"]:
            desc = f"{desc} {r['strength']}".strip()
        if r["dosage_form"]:
            desc = f"{desc} ({r['dosage_form']})".strip()
        # Quantity dispensed, with its unit of measure.
        qty = r["dispensed_quantity_base_units"]
        if r["dosage_form"]:
            qty = f"{qty} {r['dosage_form']}"
        data.append([
            P(i), P(r["dispensed_at"]), P(r["patient_full_name"]),
            P(r["patient_age"]), P(r["patient_sex"]), P(r["patient_address"]),
            P(desc), P(qty),
            P(r["prescribing_doctor_name"]), P(r["prescription_serial"]),
        ])

    col_widths = [12, 26, 36, 10, 10, 40, 50, 26, 36, 31]
    col_widths = [w * mm for w in col_widths]

    table = Table(data, colWidths=col_widths, repeatRows=1)
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1f4e5f")),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#999999")),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f2f6f7")]),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ("LEFTPADDING", (0, 0), (-1, -1), 3),
        ("RIGHTPADDING", (0, 0), (-1, -1), 3),
    ]))

    period = ""
    if from_date or to_date:
        period = f"{from_date or '...'} to {to_date or '...'}"
    loc = ", ".join(x for x in [branch["woreda"], branch["city"]] if x)
    serial = branch["efda_branch_license"] or "________________"

    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf, pagesize=landscape(A4),
        leftMargin=10 * mm, rightMargin=10 * mm,
        topMargin=10 * mm, bottomMargin=10 * mm,
        title=meta["form_no"],
    )
    story = [
        Paragraph(meta["form_no"], form_s),
        Paragraph(meta["title"], title_s),
        Paragraph(f"Name of Health Institution: {branch['name']}", sub_s),
        Paragraph(f"Address: {loc}", sub_s),
        Paragraph(f"Serial No.: {serial}", sub_s),
    ]
    if period:
        story.append(Paragraph(f"Period: {period}", sub_s))
    story += [
        Paragraph(f"{len(rows)} record(s)", sub_s),
        Spacer(1, 5 * mm),
        table,
        Spacer(1, 4 * mm),
        Paragraph(
            "Remark: Record on the "
            + ("Narcotic" if klass == "narcotic" else "Psychotropic")
            + " Drugs is required.",
            sub_s,
        ),
    ]
    doc.build(story)

    filename = f"register_{klass}_{branch_id}.pdf"
    return Response(
        content=buf.getvalue(),
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
