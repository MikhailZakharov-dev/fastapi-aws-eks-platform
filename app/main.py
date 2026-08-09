from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.config import settings
from app.db import check_connection
from app.schemas import HealthResponse


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Падаем на старте, а не отдаём 500 на каждый запрос: отказ заметнее.
    check_connection()
    yield


app = FastAPI(title=settings.app_name, lifespan=lifespan)


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    """Цель для probe; эхо-ит commit SHA текущей сборки."""
    return HealthResponse(status="ok", commit_sha=settings.commit_sha)
