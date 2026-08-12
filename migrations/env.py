from alembic import context

from app.db import engine
from app.models import Base

# Желаемое состояние для autogenerate: метаданные моделей.
target_metadata = Base.metadata

# Движок берётся из приложения, поэтому строка подключения собирается
# из тех же переменных окружения — отдельного адреса базы для миграций нет.
with engine.connect() as connection:
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()
