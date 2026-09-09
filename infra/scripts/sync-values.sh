#!/usr/bin/env bash
# Переносит в gitops-репозиторий два значения, которые меняются при каждом
# пересоздании базы: ARN секрета и адрес инстанса. Подробности — в README.md рядом.
set -euo pipefail

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITOPS_DIR="${GITOPS_DIR:-$(cd "$INFRA_DIR/../.." && pwd)/talk-booking-gitops}"

# База одна на оба окружения, поэтому ARN и хост у dev и prod совпадают.
ENVS="dev prod"

for ENV in $ENVS; do
  for f in "$GITOPS_DIR/charts/secrets/values-$ENV.yaml" "$GITOPS_DIR/charts/talk-booking/values-$ENV.yaml"; do
    [ -f "$f" ] || { echo "нет файла: $f"; echo "задай GITOPS_DIR, если репозиторий лежит в другом месте"; exit 1; }
  done
done

cd "$INFRA_DIR"

ARN=$(terraform output -raw rds_secret_arn_for_eso 2>/dev/null || true)
ENDPOINT=$(terraform output -raw rds_endpoint 2>/dev/null || true)

if [ -z "$ARN" ] || [ -z "$ENDPOINT" ]; then
  echo "terraform не отдал значения — стенд не поднят? запусти make up"
  exit 1
fi

HOST="${ENDPOINT%%:*}"

# sed возвращает 0, даже когда ничего не заменил, поэтому каждую подстановку
# проверяем следом: иначе переименованный ключ молча оставит старое значение.
replace() {
  local file="$1" key="$2" value="$3"
  sed -i.bak "s|^  ${key}: .*|  ${key}: ${value}|" "$file"
  rm -f "$file.bak"
  grep -q "^  ${key}: ${value}$" "$file" || {
    echo "не удалось записать ${key} в ${file} — ключа нет или отступ другой"
    exit 1
  }
}

for ENV in $ENVS; do
  replace "$GITOPS_DIR/charts/secrets/values-$ENV.yaml" "secretArn" "$ARN"
  replace "$GITOPS_DIR/charts/talk-booking/values-$ENV.yaml" "host" "$HOST"
done

echo "secretArn → $ARN   (dev, prod)"
echo "host      → $HOST   (dev, prod)"
echo
cd "$GITOPS_DIR"
if git diff --quiet; then
  echo "значения уже были актуальны, коммитить нечего"
else
  git --no-pager diff --stat
  echo
  echo "дальше: git add -A && git commit -m 'chore(dev): sync RDS values' && git push"
fi
