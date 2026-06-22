# infra/ — Terraform

Foundation для talk-booking: remote state (S3), VPC, EKS, ECR.

## Слои: персистентное vs эфемерное

| Слой | Ресурсы | Жизнь |
| --- | --- | --- |
| **Персистентное** | S3 state bucket, ECR | живёт всегда (дёшево); защищено `prevent_destroy` |
| **Эфемерное** | VPC, NAT, EKS | apply в начале сессии → destroy в конце (дорого) |

## Ритуал сессии

```bash
# поднять эфемерный стек (~15 мин из-за EKS control plane)
terraform apply

# доступ к кластеру (новый кластер = новый endpoint/CA → каждую сессию заново)
aws eks update-kubeconfig --name talk-booking --region eu-central-1

# ... работа ...

# снести эфемерное; персистентное (bucket + ECR) остаётся
terraform destroy -target=module.eks -target=module.vpc
```

`prevent_destroy` на bucket/ECR не даст случайно снести персистентное → teardown
делается targeted, а не голым `terraform destroy`.

## Cost

EKS CP $0.10/ч + 2× t3.small + NAT ≈ **$0.3–0.4 / сессия**.
Персистентное (S3 state, ECR-образы) — копейки/мес, не сносим.
