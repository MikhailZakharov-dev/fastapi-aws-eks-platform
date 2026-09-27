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
# Пул лениво открывает соединения по мере надобности: pool_size держит постоянно,
# max_overflow открывает на пике и закрывает при возврате. Запрос, которому не хватило
# соединения, ждёт pool_timeout и получает ошибку от самого пула — база его не видела.
engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    pool_size=settings.db_pool_size,
    max_overflow=settings.db_max_overflow,
    pool_timeout=settings.db_pool_timeout,
)


def check_connection() -> None:
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
