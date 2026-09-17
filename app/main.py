from contextlib import asynccontextmanager

from fastapi import FastAPI, Response, status
from prometheus_fastapi_instrumentator import Instrumentator, metrics
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

# Пробы стучат в /health и /ready каждые 2-10 секунд. Без исключения они составят
# подавляющее большинство «запросов» и утопят реальный трафик в счётчиках.
#
# Бакеты гистограммы с меткой handler задаём явно. Дефолт библиотеки — (0.1, 0.5, 1):
# если p95 попадает в последний бакет 1 -> +Inf, интерполировать некуда, и
# histogram_quantile возвращает последнюю конечную границу, то есть ровно 1.
# С таким дефолтом панель «p95 по ручкам» рисовала бы единицу при любых тормозах,
# а правило «p95 > 1» не сработало бы никогда.
#
# Границы выбираются ДО сбора и задним числом не меняются: ряды, уже записанные
# со старыми бакетами, так со старыми и останутся.
#
# Вызов .add() отменяет автоматическую регистрацию дефолтных метрик: набор метрик
# тот же самый, меняются только границы.
Instrumentator(excluded_handlers=["/health", "/ready", "/metrics"]).add(
    metrics.default(latency_lowr_buckets=(0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10))
).instrument(app).expose(app)


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
        talks = session.scalars(select(Talk)).all()
    return [TalkResponse.model_validate(t) for t in talks]
