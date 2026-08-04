FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends procps && rm -rf \
  /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/uv

WORKDIR /app

COPY pyproject.toml uv.lock ./
# --locked, а не --frozen: --frozen ставит ровно то, что в uv.lock, не сверяя
# его с pyproject.toml, и собирает образ без забытых зависимостей молча.
# --locked падает, если лок разошёлся с pyproject.
RUN uv sync --locked --no-dev --no-install-project

COPY app ./app

ENV PATH="/app/.venv/bin:$PATH"

EXPOSE 8000

ENTRYPOINT ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
