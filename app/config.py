from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """App config из переменных окружения (и .env, если есть)."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "talk-booking"
    # Читается из env COMMIT_SHA. В CI туда уедет $CI_COMMIT_SHA;
    # локально "unknown", чтобы /health всегда отвечал.
    commit_sha: str = "unknown"


settings = Settings()
