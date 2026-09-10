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
}
