module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "talk-booking"
  cluster_version = "1.31"

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  enable_irsa                              = true
  enable_cluster_creator_admin_permissions = true

  # CMK для envelope-шифрования Secrets не создаётся: закрывает угрозу доступа
  # к etcd на стороне AWS, которая вне модели для эфемерного учебного кластера.
  # Цена дефолта — $1/мес на каждый цикл create/destroy: удалить ключ сразу
  # нельзя, он ещё 30 дней висит в PendingDeletion и тарифицируется.
  # Подробности и условия возврата: docs/adr/17-eks-secrets-encryption-off.md
  create_kms_key            = false
  cluster_encryption_config = {}

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.small"]
      min_size       = 2
      max_size       = 2
      desired_size   = 2
    }
  }
}
