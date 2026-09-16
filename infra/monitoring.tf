resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "90.0.0"
  namespace        = "monitoring"
  create_namespace = true

  depends_on = [module.eks]

  # Постоянного тома нет: метрики живут до пересоздания пода, хранить долго незачем.
  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "6h"
  }

  # Ёмкость ноды здесь считается НЕ в памяти, а в адресах: у t3.small три ENI
  # по четыре адреса, то есть около 11 подов на ноду. Памяти при этом свободно
  # больше 90%. Метрики самих узлов в RED не участвуют — он строится по метрикам
  # приложения, поэтому слот освобождаем.
  set {
    name  = "nodeExporter.enabled"
    value = "false"
  }

  # А это включаем обратно. Алерт говорит «сломалось», дашборд обязан сказать
  # «почему», и слой «почему» приходит только отсюда: рестарты контейнеров,
  # CrashLoopBackOff, сколько реплик недоступно. Без него при срабатывании
  # AppDown панель причины показывает пустоту.
  set {
    name  = "kubeStateMetrics.enabled"
    value = "true"
  }

  # Хуки генерации сертификатов для вебхука валидации PrometheusRule: два
  # временных пода на установку. Цена выключения — синтаксически битое выражение
  # в правиле apiserver примет молча; узнаешь об этом не от kubectl, а из логов
  # оператора или по тому, что правило просто не появилось в Prometheus.
  set {
    name  = "prometheusOperator.admissionWebhooks.enabled"
    value = "false"
  }

  # Grafana наружу не торчит: ClusterIP и port-forward, Ingress не заводим —
  # он поднял бы ALB с почасовой оплатой. Пароль остаётся чартовый
  # (admin / prom-operator): в git его класть незачем, стенд живёт часы.
  # Тома тоже нет, поэтому нарисованный руками дашборд переживёт перезапуск
  # пода только если выгрузить его в ConfigMap с меткой grafana_dashboard.
  set {
    name  = "grafana.enabled"
    value = "true"
  }

  set {
    name  = "alertmanager.enabled"
    value = "true"
  }

  # Маршрут задаётся здесь, а не через set: вложенную структуру set не выразит.
  values = [yamlencode({
    alertmanager = {
      config = {
        route = {
          # Восемь упавших подов дают одно сообщение, а не восемь. Это и есть
          # основная причина, по которой Alertmanager вообще отдельный процесс.
          group_by = ["alertname", "namespace"]
          # Ждём соседние алерты, чтобы они попали в ту же пачку.
          group_wait = "30s"
          # Как часто досылать новые алерты уже существующей группы.
          group_interval = "5m"
          # Как часто напоминать, пока горит.
          repeat_interval = "1h"
          receiver        = "sink"
          # Дефолт чарта уводит алерт Watchdog в приёмник с именем "null".
          # Список receivers мы заменяем целиком (списки в helm не сливаются,
          # а замещаются), приёмника "null" больше не существует — и не обнулив
          # routes, получишь конфиг, который Alertmanager отвергнет на старте.
          routes = []
        }
        receivers = [{
          name = "sink"
          webhook_configs = [{
            url = "http://alert-sink.monitoring.svc.cluster.local:8080/"
            # Приходит и событие «потухло», не только «загорелось».
            send_resolved = true
          }]
        }]
      }
    }
  })]
}
