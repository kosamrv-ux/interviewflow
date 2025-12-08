# ============================================================
# Stage 1: builder — install dependencies into a venv
# ============================================================
FROM python:3.11-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Create and activate virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install dependencies first for layer caching
COPY requirements.txt .
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# ============================================================
# Stage 2: runtime — lean image with only the venv
# ============================================================
FROM python:3.11-slim AS runtime

# Security: non-root user
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser

# Copy the pre-built venv from builder
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /app

# Copy application source
COPY --chown=appuser:appgroup app/ ./app/

USER appuser

EXPOSE 8000

# Uvicorn with multiple workers for concurrent scoring requests.
# In GCP Cloud Run the --workers flag is ignored (single process per instance),
# but works correctly in Docker Compose with replicas.
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

CMD ["uvicorn", "app.main:app", \
     "--host", "0.0.0.0", \
     "--port", "8000", \
     "--workers", "2", \
     "--log-level", "info", \
     "--access-log"]
