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

    # Пул соединений одного процесса — часть бюджета соединений к базе, считается
    # вместе с maxReplicas HPA, поэтому приходит из окружения, а не зашит в код.
    db_pool_size: int = 5
    db_max_overflow: int = 10
    db_pool_timeout: int = 30


settings = Settings()
