# Дрейф и провалившийся sync: три оси состояния ArgoCD

## Сбой А — ручная правка в кластере (дрейф)

- **Symptom:** `kubectl -n dev scale deployment talk-booking --replicas=5` при
  `replicaCount: 1` в git. При включённом selfHeal лишние поды живут секунды и
  исчезают; при выключенном — остаются, приложение висит OutOfSync.
- **Signal:** `kubectl get applications -n argocd` → `OutOfSync / Progressing`;
  вкладка DIFF показывает `replicas: 5` (live) против `replicas: 1` (desired).
- **Cause:** желаемое состояние живёт в git, а не в кластере. Контроллер
  непрерывно сравнивает отрендеренный чарт с live-объектами; ручная правка —
  это расхождение, а не новое намерение.
- **Fix:** durable-изменение вносится коммитом в gitops-репозиторий. `kubectl`
  даёт фикс на временное окно.
- **Prevention:** selfHeal включён на dev. Важно понимать цену выключенного
  selfHeal: ручная правка не откатывается сразу, но будет молча стёрта следующим
  же несвязанным sync'ом (бамп тега от CI, чужой коммит) — отказ придёт в
  непредсказуемый момент.

## Сбой Б — схемно-невалидный манифест в git

- **Symptom:** `replicaCount: "too much, observe break"` закоммичен в
  `values-dev.yaml`. Приложение продолжает обслуживать трафик.
- **Signal:** три оси разошлись одновременно — SYNC `OutOfSync`, HEALTH
  `Healthy`, OPERATION `SyncError`:
  `error when patching ...: Invalid value: "": unrecognized type: int32`,
  `Retrying attempt #4`, затем `retried 5 times`.
  В таблице RESULT sync оказался частичным: `v1/Service` → Synced,
  `apps/v1/Deployment` → SyncFailed.
- **Cause:** Helm типы не проверяет и отрендерил строку. Патч отверг
  **kube-apiserver** на валидации схемы (`replicas` объявлен int32) — ArgoCD
  здесь клиент, а не гейткипер. Живой Deployment не изменился, поэтому старый
  ReplicaSet и поды продолжили работать.
- **Fix:** `git revert` сломавшего коммита; следующий оборот петли вернул Synced.
- **Prevention:** различать два класса плохих манифестов. Схемно-невалидный
  отвергается на входе в API — изменение не доезжает, отказ безопасный.
  **Валидный, но семантически неверный** (несуществующий тег образа,
  `replicaCount: 0`) apiserver примет, ArgoCD отрапортует Synced — и посыпется
  уже health. `Synced` означает «кластер совпал с git», а не «конфигурация
  верна»; от плохого решения защищает ревью MR, а не GitOps.
