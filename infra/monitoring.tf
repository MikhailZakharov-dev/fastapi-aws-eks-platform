resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "90.0.0"
  namespace        = "monitoring"
  create_namespace = true

  depends_on = [module.eks]

  # Grafana и Alertmanager — тема 29. Сейчас это лишняя память на двух t3.small,
  # где уже живут ArgoCD, ESO и контроллер балансировщика.
  set {
    name  = "grafana.enabled"
    value = "false"
  }

  set {
    name  = "alertmanager.enabled"
    value = "false"
  }

  # Постоянного тома нет: метрики живут до пересоздания пода, хранить долго незачем.
  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "6h"
  }

  # Ёмкость ноды здесь считается НЕ в памяти, а в адресах: у t3.small три ENI
  # по четыре адреса, то есть около 11 подов на ноду. Памяти при этом свободно
  # больше 90%. Метрики узлов и состояния кластера для RED-дашборда не нужны —
  # он строится по метрикам приложения, поэтому освобождаем слоты ими.
  set {
    name  = "nodeExporter.enabled"
    value = "false"
  }

  set {
    name  = "kubeStateMetrics.enabled"
    value = "false"
  }

  # Хуки генерации сертификатов для вебхука валидации PrometheusRule: два
  # временных пода на установку. Валидация правил нам не нужна, слоты нужны.
  set {
    name  = "prometheusOperator.admissionWebhooks.enabled"
    value = "false"
  }
}
