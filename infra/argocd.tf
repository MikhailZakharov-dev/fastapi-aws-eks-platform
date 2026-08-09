# Токен добывается лениво: data-источник читался бы в начале apply и протухал
# до того, как helm им воспользуется.
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", "eu-central-1"]
    }
  }
}

# argocd-server остаётся ClusterIP: наружу не торчит, доступ через port-forward.
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.2.1"
  namespace        = "argocd"
  create_namespace = true
}

# Единственная Application от Terraform; дальше состав кластера ведётся коммитами.
resource "helm_release" "root_app" {
  name       = "root-app"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.5"
  namespace  = "argocd"

  # CRD Application должен существовать до записи объекта такого вида.
  depends_on = [helm_release.argocd]

  values = [yamlencode({
    applications = {
      root = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = "https://gitlab.com/beaviz0405/talk-booking-gitops.git"
          targetRevision = "main"
          path           = "apps"
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = {
            selfHeal = true
            # На root prune снёс бы приложение вместе с нагрузкой.
            prune = false
          }
        }
      }
    }
  })]
}
