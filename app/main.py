from fastapi import FastAPI

from app.config import settings
from app.schemas import HealthResponse

app = FastAPI(title=settings.app_name)


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    """Цель для probe; эхо-ит commit SHA текущей сборки."""
    return HealthResponse(status="ok", commit_sha=settings.commit_sha)
