# infra/ — Terraform

Foundation для talk-booking: remote state (S3), VPC, EKS, ECR, RDS, bootstrap ArgoCD.

## Слои: персистентное vs эфемерное

| Слой | Ресурсы | Жизнь |
| --- | --- | --- |
| **Персистентное** | S3 state bucket, ECR | живёт всегда (дёшево); защищено `prevent_destroy` |
| **Эфемерное** | VPC, NAT, EKS, ArgoCD, RDS | apply в начале сессии → destroy в конце (дорого) |

## Ритуал сессии

```bash
make up          # поднять стенд (~20 мин) + обновить kubeconfig
# ... работа ...
make down        # снести эфемерное; bucket и ECR остаются
make status      # проверить, что снеслось
```

Снос идёт **списком целей**, а не голым `terraform destroy`: последний упрётся в
`prevent_destroy` на бакете состояния и ECR и не выполнится вовсе. Актуальный список
эфемерных ресурсов живёт в `Makefile` — добавляя новый ресурс в этот слой, дополняй
переменную `EPHEMERAL`, иначе он переживёт `make down` и продолжит стоить денег.

`make snapshots` показывает финальные снимки RDS, оставшиеся от прошлых сессий: при
`skip_final_snapshot = false` каждый снос оставляет по снимку, и они накапливаются.

## Cost

EKS CP $0.10/ч + 2× t3.small + NAT + RDS micro ≈ **$0.4–0.5 / сессия**.
Персистентное (S3 state, ECR-образы, снимки) — копейки/мес.

## Решения

Обоснования вынесены в ADR: [CI→AWS auth](../docs/adr/14-ci-auth-masked-vars.md) ·
[шифрование Secrets в EKS](../docs/adr/17-eks-secrets-encryption-off.md) ·
[комплект защит RDS](../docs/adr/19-rds-safety-flags.md).
