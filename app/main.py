from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.config import settings
from app.db import check_connection
from app.schemas import HealthResponse


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Недоступная база роняет контейнер на старте: k8s покажет CrashLoopBackOff.
    # Альтернатива — стартовать и отдавать 500 на каждый запрос: под считается
    # живым, и поломка ищется дольше. Вызов синхронный, но на старте это
    # безвредно — обрабатывать ещё нечего.
    check_connection()
    yield


app = FastAPI(title=settings.app_name, lifespan=lifespan)


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    """Цель для probe; эхо-ит commit SHA текущей сборки."""
    return HealthResponse(status="ok", commit_sha=settings.commit_sha)
