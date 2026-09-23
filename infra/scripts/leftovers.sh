#!/usr/bin/env bash
# Что из оплачиваемого осталось в AWS. Код возврата terraform доказательством
# сноса не считается: в теме 29 destroy оборвался на падении DNS посреди работы,
# и EKS, NAT и VPC остались бы жить. Выход 1 — если осталось хоть что-то или
# хоть одну проверку не удалось выполнить: «не смог проверить» не равно «пусто».
set -uo pipefail
R="${REGION:-eu-central-1}"
LEFT=0

check() {  # подпись, команда aws
  local name="$1"; shift
  local out
  if ! out=$("$@" 2>/dev/null); then
    printf '  %s: НЕ УДАЛОСЬ ПРОВЕРИТЬ\n' "$name"; LEFT=1; return
  fi
  out=$(echo "$out" | tr '\t' ' ' | xargs)
  if [ -n "$out" ] && [ "$out" != "None" ]; then
    printf '  %s: %s\n' "$name" "$out"; LEFT=1
  else
    printf '  %s: —\n' "$name"
  fi
}

echo "== остаток в AWS ($R) =="
check "EKS"               aws eks list-clusters --region "$R" --query 'clusters' --output text
check "RDS"               aws rds describe-db-instances --region "$R" --query 'DBInstances[].DBInstanceIdentifier' --output text
check "NAT"               aws ec2 describe-nat-gateways --region "$R" --filter Name=state,Values=pending,available,deleting --query 'NatGateways[].NatGatewayId' --output text
check "балансировщики"    aws elbv2 describe-load-balancers --region "$R" --query 'LoadBalancers[].LoadBalancerName' --output text
check "EC2"               aws ec2 describe-instances --region "$R" --filters Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId' --output text
check "Elastic IP"        aws ec2 describe-addresses --region "$R" --query 'Addresses[].AllocationId' --output text
check "EBS-тома"          aws ec2 describe-volumes --region "$R" --query 'Volumes[].VolumeId' --output text
check "VPC не дефолтные"  aws ec2 describe-vpcs --region "$R" --filters Name=isDefault,Values=false --query 'Vpcs[].VpcId' --output text

SNAP=$(aws rds describe-db-snapshots --region "$R" --snapshot-type manual \
  --query 'length(DBSnapshots)' --output text 2>/dev/null || echo "?")
echo "  (финальных снимков RDS: $SNAP — копятся с каждым сносом; список: make snapshots)"

if [ "$LEFT" = 1 ]; then
  echo "ОСТАЛОСЬ ПЛАТНОЕ ИЛИ НЕ ПРОВЕРЕНО — стенд снесён не до конца"
  exit 1
fi
echo "чисто: почасово оплачиваемого не осталось"
