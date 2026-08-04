from sqlalchemy import URL, create_engine, text

from app.config import settings

# URL.create экранирует пароль сам. Сгенерированный RDS пароль может содержать
# @ / : ? — при склейке строки подключения вручную такой пароль ломает адрес.
DATABASE_URL = URL.create(
    "postgresql+psycopg",
    username=settings.db_user,
    password=settings.db_password,
    host=settings.db_host,
    port=settings.db_port,
    database=settings.db_name,
)

# pool_pre_ping проверяет соединение перед выдачей из пула: сервер мог закрыть
# его за время простоя, и без проверки это всплывёт как ошибка первого запроса.
engine = create_engine(DATABASE_URL, pool_pre_ping=True)


def check_connection() -> None:
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
