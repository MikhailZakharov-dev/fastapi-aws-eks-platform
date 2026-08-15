CLUSTER := talk-booking
REGION  := eu-central-1

# Стоимость часа стенда в долларах: EKS control plane 0.10 + две ноды t3.small 0.042
# + NAT Gateway 0.045 + RDS t3.micro 0.017. ALB, если поднят, добавляет ещё 0.023.
RATE := 0.21

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

.PHONY: up down plan kubeconfig status snapshots cost

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

cost: ## сколько стенд уже живёт и во сколько обошёлся
	@CREATED=$$(aws eks describe-cluster --name $(CLUSTER) --region $(REGION) \
	  --query 'cluster.createdAt' --output text 2>/dev/null); \
	if [ -z "$$CREATED" ]; then \
	  echo "стенд снесён — счётчик не тикает"; \
	else \
	  python3 -c 'import datetime,sys; \
	    c=datetime.datetime.fromisoformat(sys.argv[1].replace("Z","+00:00")); \
	    h=(datetime.datetime.now(c.tzinfo)-c).total_seconds()/3600; \
	    print(f"поднят: {h:.1f} ч  ·  уже ~${h*float(sys.argv[2]):.2f}"); \
	    print(f"каждые сутки простоя добавляют ~${24*float(sys.argv[2]):.2f}")' \
	    "$$CREATED" "$(RATE)"; \
	fi

snapshots: ## финальные снимки RDS от прошлых сессий (накапливаются и стоят денег)
	@aws rds describe-db-snapshots --region $(REGION) --snapshot-type manual \
	  --query 'DBSnapshots[].{id:DBSnapshotIdentifier,created:SnapshotCreateTime,gb:AllocatedStorage}' \
	  --output table
