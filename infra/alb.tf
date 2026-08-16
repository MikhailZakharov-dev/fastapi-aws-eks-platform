# Роль может принять только ServiceAccount контроллера и только с токеном для STS.
data "aws_iam_policy_document" "alb_controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "talk-booking-alb-controller"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume.json
}

# Политика взята из проекта контроллера без правок: 16 блоков и 86 действий,
# сузить её вручную нельзя — контроллер создаёт балансировщики, слушатели,
# целевые группы и правит security groups.
resource "aws_iam_role_policy" "alb_controller" {
  name   = "aws-load-balancer-controller"
  role   = aws_iam_role.alb_controller.name
  policy = file("${path.module}/policies/aws-load-balancer-controller.json")
}

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.5.0"
  namespace  = "kube-system"

  depends_on = [module.eks]

  # Без имени кластера контроллер не найдёт свои узлы и подсети.
  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.alb_controller.arn
  }

  # Заданы явно, чтобы контроллер не тратил время на определение при старте.
  set {
    name  = "region"
    value = "eu-central-1"
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }
}
