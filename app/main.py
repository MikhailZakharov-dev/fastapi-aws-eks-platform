from contextlib import asynccontextmanager

from fastapi import FastAPI, Response, status
from sqlalchemy import select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.config import settings
from app.db import check_connection, engine
from app.models import Talk
from app.schemas import HealthResponse, TalkResponse


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


@app.get("/ready", response_model=HealthResponse)
def ready(response: Response) -> HealthResponse:
    """Цель readiness-пробы: пускаем трафик, только если база отвечает."""
    try:
        check_connection()
    except SQLAlchemyError:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return HealthResponse(status="db unavailable", commit_sha=settings.commit_sha)
    return HealthResponse(status="ok", commit_sha=settings.commit_sha)


@app.get("/talks", response_model=list[TalkResponse])
def list_talks() -> list[TalkResponse]:
    with Session(engine) as session:
        talks = session.scalars(select(Talk).order_by(Talk.tittle)).all()
    return [TalkResponse.model_validate(t) for t in talks]
