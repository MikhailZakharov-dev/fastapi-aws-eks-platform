#!/usr/bin/env bash
# Удаляет все ExternalSecret ДО сноса чарта ESO.
#
# ESO вешает на каждый ExternalSecret финализатор, который снимает только его
# собственный контроллер. Снос чарта удаляет CRD, удаление CRD каскадом удаляет
# все ExternalSecret — но контроллер к этому моменту снесён тем же uninstall, а
# ноды под ним гаснут параллельно. Снять финализатор некому: объекты висят в
# Terminating, CRD — в InstanceDeletionInProgress, helm ждёт и падает по таймауту
# (тема 30). Поэтому удаляем их сами, пока контроллер жив.
#
# Вызывать ПОСЛЕ снятия автосинка: иначе ArgoCD вернёт объекты обратно.
set -uo pipefail

if ! kubectl get crd externalsecrets.external-secrets.io >/dev/null 2>&1; then
  echo "(ESO в кластере нет или нет самого кластера — пропускаю)"
  exit 0
fi

echo "== удаляю ExternalSecret, пока контроллер ESO жив и снимет свои финализаторы =="
if kubectl delete externalsecrets.external-secrets.io --all --all-namespaces \
     --ignore-not-found --timeout=2m; then
  exit 0
fi

# Сюда попадаем, когда контроллер уже мёртв (например, ноды погашены прошлым
# неудачным сносом). Снимаем финализаторы руками: кластер всё равно уходит
# целиком, а в Secrets Manager удаление ExternalSecret ничего не трогает.
echo "== контроллер не снял финализаторы за 2 минуты — снимаю их сам =="
kubectl get externalsecrets.external-secrets.io --all-namespaces \
  -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name}{"\n"}{end}' \
  | while read -r NS NAME; do
      [ -z "$NAME" ] && continue
      kubectl -n "$NS" patch externalsecret "$NAME" --type=merge \
        -p '{"metadata":{"finalizers":null}}'
    done
