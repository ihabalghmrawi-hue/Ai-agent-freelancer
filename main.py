# ============================================================
# FreelancePilot AI — FastAPI Backend
# apps/api/app/main.py
# ============================================================

from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse
import time

from app.config import settings
from app.core.database import engine, Base
from app.middleware.rate_limit import RateLimitMiddleware
from app.middleware.tenant_middleware import TenantMiddleware
from app.routers import (
    auth, workspaces, jobs, proposals,
    crm, analytics, billing, notifications,
    automations, admin, profiles
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    print("✅ FreelancePilot AI API started")
    yield
    # Shutdown
    await engine.dispose()
    print("🔴 API shutdown")


app = FastAPI(
    title="FreelancePilot AI API",
    description="AI-powered freelance automation platform",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json",
    lifespan=lifespan,
)

# ── Middleware ──────────────────────────────────────────────

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(GZipMiddleware, minimum_size=1000)
app.add_middleware(RateLimitMiddleware)
app.add_middleware(TenantMiddleware)


@app.middleware("http")
async def add_process_time_header(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    response.headers["X-Process-Time"] = str(round(time.perf_counter() - start, 4))
    return response


# ── Exception Handlers ──────────────────────────────────────

@app.exception_handler(404)
async def not_found(request: Request, exc):
    return JSONResponse(status_code=404, content={"error": "Not found", "path": str(request.url)})


@app.exception_handler(500)
async def server_error(request: Request, exc):
    return JSONResponse(status_code=500, content={"error": "Internal server error"})


# ── Routers ─────────────────────────────────────────────────

PREFIX = "/api/v1"

app.include_router(auth.router,          prefix=f"{PREFIX}/auth",          tags=["Authentication"])
app.include_router(workspaces.router,    prefix=f"{PREFIX}/workspaces",    tags=["Workspaces"])
app.include_router(profiles.router,      prefix=f"{PREFIX}/profiles",      tags=["Freelancer Profiles"])
app.include_router(jobs.router,          prefix=f"{PREFIX}/jobs",          tags=["Jobs"])
app.include_router(proposals.router,     prefix=f"{PREFIX}/proposals",     tags=["Proposals"])
app.include_router(crm.router,           prefix=f"{PREFIX}/crm",           tags=["CRM"])
app.include_router(analytics.router,     prefix=f"{PREFIX}/analytics",     tags=["Analytics"])
app.include_router(billing.router,       prefix=f"{PREFIX}/billing",       tags=["Billing"])
app.include_router(notifications.router, prefix=f"{PREFIX}/notifications", tags=["Notifications"])
app.include_router(automations.router,   prefix=f"{PREFIX}/automations",   tags=["Automations"])
app.include_router(admin.router,         prefix=f"{PREFIX}/admin",         tags=["Admin"])


@app.get("/health", tags=["Health"])
async def health():
    return {"status": "ok", "service": "FreelancePilot AI API"}
