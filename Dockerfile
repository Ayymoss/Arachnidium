# syntax=docker/dockerfile:1

ARG PYTHON_VERSION=3.12
ARG BUN_VERSION=1

# Python dependencies, installed from uv.lock into /app/.venv
FROM python:${PYTHON_VERSION}-slim AS python-deps
COPY --from=ghcr.io/astral-sh/uv:0.12 /uv /bin/uv
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never
WORKDIR /app
COPY pyproject.toml uv.lock .python-version ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project

# Bun API dependencies, installed from bun.lock
FROM oven/bun:${BUN_VERSION} AS bun-deps
WORKDIR /app/bun-api
COPY bun-api/package.json bun-api/bun.lock ./
RUN bun install --frozen-lockfile --production --omit=peer

FROM python:${PYTHON_VERSION}-slim

# addon.py imports tkinter even when the GUI is disabled.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libtk8.6 \
 && rm -rf /var/lib/apt/lists/*

RUN useradd --uid 1000 --create-home app \
 && mkdir /data \
 && chown app:app /data

WORKDIR /app

# Same layout as the release archives: addon.py starts bun-api/bun itself.
COPY --from=python-deps /app/.venv .venv
COPY --from=bun-deps /usr/local/bin/bun bun-api/bun
COPY --from=bun-deps /app/bun-api/node_modules bun-api/node_modules
COPY bun-api/package.json bun-api/index.ts bun-api/
COPY main.py addon.py ./
COPY defaults.json docker/
COPY --chown=app defaults.json ./
COPY --chmod=755 docker/entrypoint.py docker/wg-qr docker/

# Arachnidium reads and writes these relative to the working directory, so
# point them (and mitmproxy's CA directory) into the /data volume.
RUN ln -s /data/wg-keys.json wg-keys.json \
 && ln -s /data/wireguard.cfg wireguard.cfg \
 && ln -s /data/mitmproxy /home/app/.mitmproxy

ENV PATH=/app/.venv/bin:/app/docker:$PATH \
    PYTHONUNBUFFERED=1

USER app
VOLUME /data
EXPOSE 51820/udp

ENTRYPOINT ["entrypoint.py"]
CMD ["python", "main.py"]
