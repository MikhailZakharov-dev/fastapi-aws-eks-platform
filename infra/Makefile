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

.PHONY: up down orphans plan kubeconfig status snapshots cost values

up: ## поднять стенд (~20 мин) и обновить kubeconfig
	terraform apply
	$(MAKE) kubeconfig

down: ## снести эфемерный слой; бакет состояния и ECR остаются
	@echo "== удаляю Ingress, чтобы контроллер успел снести ALB =="
	@kubectl delete ingress --all --all-namespaces --ignore-not-found --timeout=3m 2>/dev/null \
	  || echo "(кластера нет или Ingress отсутствует — пропускаю)"
	@echo "== жду, пока балансировщик исчезнет =="
	@for i in $$(seq 1 20); do \
	  COUNT=$$(aws elbv2 describe-load-balancers --region $(REGION) \
	    --query 'length(LoadBalancers)' --output text 2>/dev/null || echo 0); \
	  [ "$$COUNT" = "0" ] && break; \
	  sleep 10; \
	done
	@# Балансировщик держит сетевые интерфейсы в подсетях, и terraform не сможет
	@# удалить VPC, пока они там. Контроллер к этому моменту уже мог уехать вместе
	@# с кластером, и тогда снимать финализатор с Ingress будет некому — поэтому
	@# останавливаемся здесь, а не бьёмся об ошибку зависимостей.
	@COUNT=$$(aws elbv2 describe-load-balancers --region $(REGION) \
	  --query 'length(LoadBalancers)' --output text 2>/dev/null || echo 0); \
	if [ "$$COUNT" != "0" ]; then \
	  echo ""; \
	  echo "ОСТАНОВКА: балансировщик всё ещё жив, снос VPC упрётся в его интерфейсы."; \
	  echo "Разберись с ним и повтори: make orphans"; \
	  exit 1; \
	fi
	terraform destroy $(EPHEMERAL)

orphans: ## удалить осиротевшие ALB и target groups, когда контроллера уже нет
	@echo "== балансировщики =="
	@for ARN in $$(aws elbv2 describe-load-balancers --region $(REGION) \
	  --query 'LoadBalancers[].LoadBalancerArn' --output text); do \
	  echo "удаляю $$ARN"; \
	  aws elbv2 delete-load-balancer --region $(REGION) --load-balancer-arn "$$ARN"; \
	done
	@echo "== целевые группы =="
	@for ARN in $$(aws elbv2 describe-target-groups --region $(REGION) \
	  --query 'TargetGroups[].TargetGroupArn' --output text); do \
	  echo "удаляю $$ARN"; \
	  aws elbv2 delete-target-group --region $(REGION) --target-group-arn "$$ARN" || true; \
	done
	@echo "== снимаю финализаторы с Ingress (контроллера нет, снять их больше некому) =="
	@kubectl get ingress --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name}{"\n"}{end}' 2>/dev/null \
	  | while read NS NAME; do \
	      [ -z "$$NAME" ] && continue; \
	      kubectl -n $$NS patch ingress $$NAME --type=merge -p '{"metadata":{"finalizers":null}}'; \
	    done || echo "(кластера нет — пропускаю)"
	@# Контроллер заводит собственные security groups, которых нет в state Terraform.
	@# Они переживают destroy и держат VPC — узнаются по тегу его авторства.
	@echo "== security groups, созданные контроллером =="
	@for SG in $$(aws ec2 describe-security-groups --region $(REGION) \
	  --filters Name=tag:elbv2.k8s.aws/cluster,Values=$(CLUSTER) \
	  --query 'SecurityGroups[].GroupId' --output text 2>/dev/null); do \
	  echo "удаляю $$SG"; \
	  aws ec2 delete-security-group --region $(REGION) --group-id "$$SG" || true; \
	done
	@echo "готово, теперь можно make down"

values: ## перенести ARN секрета и адрес базы в values-dev gitops-репозитория
	@./scripts/sync-values.sh

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
