"""
NovaDawa API — main entry point.

Start locally:
    uvicorn app.main:app --reload --port 8000

Interactive docs:
    http://localhost:8000/docs
"""
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.database import create_pool
from app.routers.health import router as health_router
from app.routers.drugs import router as drugs_router
from app.routers.dosing import router as dosing_router
from app.routers.tenants import router as tenants_router
from app.routers.inventory import router as inventory_router

logging.basicConfig(level=settings.log_level)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Create the DB pool on startup, close it on shutdown."""
    logger.info("Starting NovaDawa API (env=%s)", settings.app_env)
    app.state.db_pool = await create_pool()
    logger.info("Database pool ready (min=%d max=%d)", settings.db_pool_min, settings.db_pool_max)
    yield
    await app.state.db_pool.close()
    logger.info("Database pool closed.")


app = FastAPI(
    title="NovaDawa API",
    description="Cloud pharmacy management system for Ethiopian retail pharmacies.",
    version="0.1.0",
    lifespan=lifespan,
    # Hide docs in production
    docs_url=None if settings.is_production else "/docs",
    redoc_url=None if settings.is_production else "/redoc",
)

# CORS — tighten origins in production
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if not settings.is_production else ["https://novadawa.com"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Routers
app.include_router(health_router)
app.include_router(drugs_router)
app.include_router(dosing_router)
app.include_router(tenants_router)
app.include_router(inventory_router)
