from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """App config из переменных окружения (и .env, если есть)."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "talk-booking"
    # В CI сюда уезжает $CI_COMMIT_SHA; локально "unknown".
    commit_sha: str = "unknown"

    db_host: str = "localhost"
    db_port: int = 5432
    db_user: str = "app"
    db_password: str = ""
    db_name: str = "talkbooking"


settings = Settings()
