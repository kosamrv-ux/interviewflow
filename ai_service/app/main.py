"""
InterviewFlow AI Scoring Service

FastAPI application that receives interview transcripts and code submissions,
calls Vertex AI (Gemini 1.5 Pro), and returns structured candidate scorecards.
"""

import logging
import time
from contextlib import asynccontextmanager
from typing import AsyncGenerator

import structlog
import uvicorn
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

from app.scoring.router import router as scoring_router
from app.config import get_settings

logger = structlog.get_logger(__name__)

settings = get_settings()

# ─── Metrics ─────────────────────────────────────────────────────────────────

REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "path", "status_code"],
)

REQUEST_DURATION = Histogram(
    "http_request_duration_seconds",
    "HTTP request duration in seconds",
    ["method", "path"],
    buckets=[0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0, 30.0],
)

SCORING_DURATION = Histogram(
    "scoring_duration_seconds",
    "AI scoring pipeline duration",
    buckets=[1.0, 2.0, 5.0, 10.0, 20.0, 30.0, 60.0],
)


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncGenerator[None, None]:
    """Application lifecycle: startup and shutdown hooks."""
    logger.info(
        "AI scoring service starting",
        environment=settings.environment,
        vertex_project=settings.vertex_ai_project,
        vertex_location=settings.vertex_ai_location,
    )
    yield
    logger.info("AI scoring service shutting down")


app = FastAPI(
    title="InterviewFlow AI Scoring Service",
    description="Analyzes interview transcripts and code submissions using Vertex AI Gemini",
    version="1.0.0",
    docs_url="/docs" if settings.environment != "production" else None,
    redoc_url=None,
    lifespan=lifespan,
)

# ─── Middleware ───────────────────────────────────────────────────────────────

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:4000"],  # Phoenix API only
    allow_methods=["POST", "GET"],
    allow_headers=["*"],
)


@app.middleware("http")
async def metrics_middleware(request: Request, call_next: object) -> Response:
    start = time.perf_counter()
    response = await call_next(request)  # type: ignore[operator]
    duration = time.perf_counter() - start

    REQUEST_COUNT.labels(
        method=request.method,
        path=request.url.path,
        status_code=response.status_code,
    ).inc()
    REQUEST_DURATION.labels(method=request.method, path=request.url.path).observe(duration)

    return response


@app.middleware("http")
async def request_id_middleware(request: Request, call_next: object) -> Response:
    import uuid

    request_id = request.headers.get("x-request-id", str(uuid.uuid4()))
    structlog.contextvars.bind_contextvars(request_id=request_id)

    response = await call_next(request)  # type: ignore[operator]
    response.headers["x-request-id"] = request_id  # type: ignore[union-attr]
    return response


# ─── Routes ──────────────────────────────────────────────────────────────────

app.include_router(scoring_router)


@app.get("/health")
async def health_check() -> dict[str, str]:
    return {"status": "ok", "service": "ai_scoring"}


@app.get("/metrics")
async def metrics() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.error("Unhandled exception", error=str(exc), path=request.url.path)
    return JSONResponse(
        status_code=500,
        content={"error": "internal_server_error", "message": "An unexpected error occurred"},
    )


if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=settings.port,
        reload=settings.environment == "development",
        log_level=settings.log_level.lower(),
    )
