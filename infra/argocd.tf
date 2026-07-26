data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

# Ставит CRD Application + поды ArgoCD. argocd-server остаётся ClusterIP:
# наружу не торчит, доступ через port-forward.
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.2.1"
  namespace        = "argocd"
  create_namespace = true
}

# Единственная Application, которую создаёт Terraform. Дальше состав кластера
# ведётся коммитами в apps/ этого же репозитория.
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
            # prune выключен намеренно: на root ошибка снесла бы приложение
            # целиком вместе с его нагрузкой.
            prune = false
          }
        }
      }
    }
  })]
}
