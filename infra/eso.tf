# Роль может принять только этот ServiceAccount и только с токеном для STS.
data "aws_iam_policy_document" "eso_assume" {
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
      values   = ["system:serviceaccount:external-secrets:external-secrets"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "talk-booking-eso"
  assume_role_policy = data.aws_iam_policy_document.eso_assume.json
}

# Доступ к одному секрету; ARN меняется при пересоздании базы.
resource "aws_iam_role_policy" "eso" {
  name = "read-db-secret"
  role = aws_iam_role.eso.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = [aws_db_instance.app.master_user_secret[0].secret_arn]
    }]
  })
}

resource "helm_release" "eso" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "2.8.0"
  namespace        = "external-secrets"
  create_namespace = true

  depends_on = [helm_release.argocd]

  # IRSA: вебхук EKS положит в под токен и переменные для STS.
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.eso.arn
  }
}

output "rds_secret_arn_for_eso" {
  description = "ARN секрета RDS — подставить в values-dev.yaml gitops-репозитория"
  value       = aws_db_instance.app.master_user_secret[0].secret_arn
}
