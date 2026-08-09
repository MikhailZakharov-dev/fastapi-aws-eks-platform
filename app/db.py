from sqlalchemy import URL, create_engine, text

from app.config import settings

# URL.create экранирует пароль: сгенерированный RDS может содержать @ / : ?
DATABASE_URL = URL.create(
    "postgresql+psycopg",
    username=settings.db_user,
    password=settings.db_password,
    host=settings.db_host,
    port=settings.db_port,
    database=settings.db_name,
)

# pool_pre_ping отсеивает соединения, закрытые сервером за время простоя.
engine = create_engine(DATABASE_URL, pool_pre_ping=True)


def check_connection() -> None:
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
