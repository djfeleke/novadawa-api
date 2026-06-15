from fastapi import APIRouter, Depends
import asyncpg
from app.database import get_db

router = APIRouter(tags=["health"])


@router.get("/health")
async def health(db: asyncpg.Connection = Depends(get_db)):
    """
    Liveness + DB connectivity check.
    Returns drug catalog size so you can confirm the seed is live.
    """
    row = await db.fetchrow(
        """
        SELECT
            (SELECT count(*) FROM drug)                     AS drugs,
            (SELECT count(*) FROM drug_sku)                 AS skus,
            (SELECT count(*) FROM clinical_reference)       AS monographs,
            (SELECT count(*) FROM drug_interaction_cache)   AS interactions
        """
    )
    return {
        "status": "ok",
        "catalog": {
            "drugs": row["drugs"],
            "skus": row["skus"],
            "monographs": row["monographs"],
            "interactions": row["interactions"],
        },
    }
