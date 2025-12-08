# ============================================================
# Stage 1: deps — fetch and compile only Mix dependencies
# ============================================================
FROM elixir:1.16-alpine AS deps

RUN apk add --no-cache build-base git nodejs npm

WORKDIR /app

# Copy manifests first so Docker can cache the dep layer
COPY mix.exs mix.lock ./
COPY config/ config/

RUN mix local.hex --force && \
    mix local.rebar --force && \
    MIX_ENV=prod mix deps.get --only prod && \
    MIX_ENV=prod mix deps.compile

# ============================================================
# Stage 2: build — compile application and generate release
# ============================================================
FROM deps AS build

COPY lib/ lib/
COPY priv/ priv/

# Compile and assemble the Distillery-style Mix release
RUN MIX_ENV=prod mix compile && \
    MIX_ENV=prod mix phx.digest && \
    MIX_ENV=prod mix release interviewflow

# ============================================================
# Stage 3: runtime — minimal Alpine image
# ============================================================
FROM alpine:3.19 AS runtime

# Runtime deps only — no compilers
RUN apk add --no-cache \
    libstdc++ \
    openssl \
    ncurses-libs \
    ca-certificates \
    tzdata

# Non-root user for security
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy only the assembled release from the build stage
COPY --from=build --chown=appuser:appgroup /app/_build/prod/rel/interviewflow ./

USER appuser

EXPOSE 4000

# Health check — the /health endpoint returns 200 with no DB dependency
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
  CMD wget -qO- http://localhost:4000/api/v1/health || exit 1

# bin/interviewflow server starts the Cowboy listener
CMD ["bin/interviewflow", "server"]
