# talk-booking

Build-to-learn платформа (production-витрина на AWS/EKS). Цель и план трека — в волте
(`prod-infra-fastapi-aws/`). Этот репо: `app/` (FastAPI «коробка») + позже `infra/`
(Terraform) + `.gitlab-ci.yml` + `docs/`.

## app/ — запуск локально (uv)

```bash
uv sync                                   # .venv + зависимости (Python 3.12, пин в .python-version)
uv run uvicorn app.main:app --reload
curl localhost:8000/health                # {"status":"ok","commit_sha":"unknown"}
```

`commit_sha` приходит из env `COMMIT_SHA` (дефолт `unknown`); в CI туда уедет `$CI_COMMIT_SHA`:

```bash
COMMIT_SHA=abc1234 uv run uvicorn app.main:app
```

## Линтинг (ruff)

```bash
uv run ruff check .        # линт (правила в pyproject.toml: E,F,I,B,UP,SIM)
uv run ruff format .       # автоформат
```
