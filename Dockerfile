FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends procps && rm -rf \
  /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/uv

WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

COPY app ./app

ENV PATH="/app/.venv/bin:$PATH"

EXPOSE 8000

ENTRYPOINT ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
