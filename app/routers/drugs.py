"""
Drug catalog endpoints.

  GET /api/v1/drugs/search?q=amoxicilin&limit=20
      Fuzzy drug name search via pg_trgm + prefix fallback.
      Public in dev (REQUIRE_AUTH=false); auth required in production.

  GET /api/v1/drugs/{drug_id}
      Full drug detail including dosage forms and interaction partner names.

  GET /api/v1/drugs/{drug_id}/clinical
      EMF clinical monograph for a drug (indications, dosing, contraindications,
      side effects, cautions, storage).
"""
from typing import Optional
import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.auth.firebase import get_current_user
from app.database import get_db
from app.schemas.drug import DrugDetail, DrugSearchResponse, DrugSearchResult, ClinicalReference

router = APIRouter(prefix="/api/v1/drugs", tags=["drugs"])

# Minimum similarity score for pg_trgm fuzzy matches.
# 0.2 is intentionally low to catch bad typos ("amoxiciln" → "Amoxicillin").
SIMILARITY_THRESHOLD = 0.2


@router.get("/search", response_model=DrugSearchResponse)
async def search_drugs(
    q: str = Query(..., min_length=2, description="Drug name (typos tolerated)"),
    limit: int = Query(default=20, ge=1, le=100),
    community_only: bool = Query(default=False, description="Filter to community-pharmacy approved drugs only"),
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """
    Fuzzy drug name search powered by pg_trgm.

    Returns ranked results — highest similarity first. Also catches prefix
    matches (e.g. "Amo" → Amoxicillin) that trigram similarity might rank low.

    Example:
      GET /api/v1/drugs/search?q=amoxicilin
      → Amoxicillin (score 0.77), Ampicillin (0.38), ...
    """
    prefix_pattern = f"{q}%"
    community_filter = "AND d.is_community_pharmacy_approved = TRUE" if community_only else ""

    rows = await db.fetch(
        f"""
        WITH matches AS (
            SELECT
                d.id,
                d.inn_name,
                d.aware_category::text,
                d.therapeutic_category,
                d.pharmacological_class,
                d.is_community_pharmacy_approved,
                d.controlled_substance,
                d.prescription_required,
                d.who_not_recommended,
                similarity(d.inn_name, $1) AS score
            FROM drug d
            WHERE (
                similarity(d.inn_name, $1) > $3
                OR d.inn_name ILIKE $2
            )
            {community_filter}
            ORDER BY score DESC, d.inn_name
            LIMIT $4
        )
        SELECT
            m.*,
            ARRAY_REMOVE(
                ARRAY_AGG(DISTINCT
                    s.dosage_form::text || COALESCE(' ' || s.strength, '')
                ), NULL
            ) AS dosage_forms
        FROM matches m
        LEFT JOIN drug_sku s ON s.drug_id = m.id
        GROUP BY
            m.id, m.inn_name, m.aware_category, m.therapeutic_category,
            m.pharmacological_class, m.is_community_pharmacy_approved,
            m.controlled_substance, m.prescription_required,
            m.who_not_recommended, m.score
        ORDER BY m.score DESC, m.inn_name
        """,
        q,               # $1 — trigram query
        prefix_pattern,  # $2 — prefix ILIKE
        SIMILARITY_THRESHOLD,  # $3
        limit,           # $4
    )

    results = [
        DrugSearchResult(
            id=str(r["id"]),
            inn_name=r["inn_name"],
            aware_category=r["aware_category"],
            therapeutic_category=r["therapeutic_category"],
            pharmacological_class=r["pharmacological_class"],
            is_community_pharmacy_approved=r["is_community_pharmacy_approved"],
            controlled_substance=r["controlled_substance"],
            prescription_required=r["prescription_required"],
            who_not_recommended=r["who_not_recommended"],
            dosage_forms=sorted(r["dosage_forms"] or []),
            similarity_score=round(float(r["score"]), 4),
        )
        for r in rows
    ]

    return DrugSearchResponse(query=q, total=len(results), results=results)


@router.get("/{drug_id}", response_model=DrugDetail)
async def get_drug(
    drug_id: str,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """
    Full drug detail — dosage forms, AWaRe category, compliance flags,
    and the names of all known interaction partners.
    """
    drug = await db.fetchrow(
        """
        SELECT
            d.id, d.inn_name, d.amharic_name, d.aware_category::text,
            d.atc_code, d.therapeutic_category, d.pharmacological_class,
            d.is_on_eeml, d.prescription_required, d.controlled_substance,
            d.is_community_pharmacy_approved, d.who_not_recommended,
            ARRAY_REMOVE(
                ARRAY_AGG(DISTINCT s.dosage_form::text || COALESCE(' ' || s.strength, '')),
                NULL
            ) AS dosage_forms
        FROM drug d
        LEFT JOIN drug_sku s ON s.drug_id = d.id
        WHERE d.id = $1
        GROUP BY d.id
        """,
        drug_id,
    )

    if not drug:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Drug not found.")

    # Interaction partner names (both sides of the pair)
    interaction_rows = await db.fetch(
        """
        SELECT
            CASE WHEN drug_a_id = $1 THEN drug_b_name ELSE drug_a_name END AS partner
        FROM drug_interaction_cache
        WHERE drug_a_id = $1 OR drug_b_id = $1
        ORDER BY partner
        """,
        drug_id,
    )
    interactions = [r["partner"] for r in interaction_rows]

    # Clinical monograph (may not exist for every drug)
    clinical_row = await db.fetchrow(
        "SELECT * FROM clinical_reference WHERE drug_id = $1",
        drug_id,
    )
    clinical = ClinicalReference(**dict(clinical_row)) if clinical_row else None

    return DrugDetail(
        id=str(drug["id"]),
        inn_name=drug["inn_name"],
        amharic_name=drug["amharic_name"],
        aware_category=drug["aware_category"],
        atc_code=drug["atc_code"],
        therapeutic_category=drug["therapeutic_category"],
        pharmacological_class=drug["pharmacological_class"],
        is_on_eeml=drug["is_on_eeml"],
        prescription_required=drug["prescription_required"],
        controlled_substance=drug["controlled_substance"],
        is_community_pharmacy_approved=drug["is_community_pharmacy_approved"],
        who_not_recommended=drug["who_not_recommended"],
        dosage_forms=sorted(drug["dosage_forms"] or []),
        clinical_reference=clinical,
        interactions=interactions,
    )


@router.get("/{drug_id}/clinical", response_model=ClinicalReference)
async def get_clinical_reference(
    drug_id: str,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """
    EMF clinical monograph for a drug — indications, dosing, contraindications,
    side effects, cautions, storage. Sourced from Ethiopian Medicines Formulary
    3rd Edition 2025.
    """
    row = await db.fetchrow(
        "SELECT * FROM clinical_reference WHERE drug_id = $1",
        drug_id,
    )
    if not row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No clinical reference found for this drug.",
        )
    return ClinicalReference(**dict(row))
