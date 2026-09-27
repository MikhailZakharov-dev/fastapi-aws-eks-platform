module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "talk-booking"
  cluster_version = "1.31"

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  enable_irsa                              = true
  enable_cluster_creator_admin_permissions = true

  # CMK для envelope-шифрования Secrets не создаётся: каждый цикл create/destroy
  # оставлял бы ключ в PendingDeletion на 30 дней с оплатой.
  # См. docs/adr/17-eks-secrets-encryption-off.md
  create_kms_key            = false
  cluster_encryption_config = {}

  # HPA получает цифры только через API metrics.k8s.io, а его отдаёт metrics-server.
  # Аддон EKS: версию под кластер подбирает AWS, модуль ставит его после групп нод.
  cluster_addons = {
    metrics-server = {}
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.small"]
      # Ёмкость ноды здесь считается в АДРЕСАХ, а не в памяти: у t3.small три ENI
      # по четыре адреса, то есть около 11 подов. Двух нод перестало хватать, как
      # только добавился стек мониторинга. Третья нода дешевле перехода на
      # t3.medium и добавляется масштабированием, без замены существующих.
      #
      # desired_size модуль применяет ТОЛЬКО при создании группы и дальше
      # игнорирует, чтобы не воевать с автоскейлером. На живом кластере правка
      # этого числа молча ничего не делает — apply рапортует успех, размер прежний.
      # Менять размер работающей группы: aws eks update-nodegroup-config.
      min_size     = 2
      max_size     = 3
      desired_size = 3
    }
  }
}
