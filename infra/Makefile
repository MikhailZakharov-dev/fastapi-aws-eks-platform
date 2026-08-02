CLUSTER := talk-booking
REGION  := eu-central-1

# Эфемерный слой — всё, что поднимается и сносится каждую сессию.
# Персистентное (бакет состояния, ECR) защищено prevent_destroy и сюда НЕ входит:
# голый `terraform destroy` на нём падает, поэтому снос идёт списком целей.
EPHEMERAL := \
	-target=helm_release.root_app \
	-target=helm_release.argocd \
	-target=aws_db_instance.app \
	-target=aws_db_subnet_group.app \
	-target=aws_vpc_security_group_ingress_rule.rds_from_nodes \
	-target=aws_security_group.rds \
	-target=random_id.snapshot_suffix \
	-target=module.eks \
	-target=module.vpc

.PHONY: up down plan kubeconfig status snapshots

up: ## поднять стенд (~20 мин) и обновить kubeconfig
	terraform apply
	$(MAKE) kubeconfig

down: ## снести эфемерный слой; бакет состояния и ECR остаются
	terraform destroy $(EPHEMERAL)

plan: ## посчитать план, ничего не меняя
	terraform plan

kubeconfig: ## новый кластер = новый endpoint и CA, обновлять каждую сессию
	aws eks update-kubeconfig --name $(CLUSTER) --region $(REGION)

status: ## что реально живо в облаке (пусто = стенд снесён)
	@echo "== EKS =="
	@aws eks list-clusters --region $(REGION) --output text
	@echo "== RDS =="
	@aws rds describe-db-instances --region $(REGION) \
	  --query 'DBInstances[].DBInstanceIdentifier' --output text

snapshots: ## финальные снимки RDS от прошлых сессий (накапливаются и стоят денег)
	@aws rds describe-db-snapshots --region $(REGION) --snapshot-type manual \
	  --query 'DBSnapshots[].{id:DBSnapshotIdentifier,created:SnapshotCreateTime,gb:AllocatedStorage}' \
	  --output table
