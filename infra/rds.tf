resource "aws_db_subnet_group" "app" {
  name       = "talk-booking"
  subnet_ids = module.vpc.private_subnets
}

# egress намеренно не объявлен: RDS не инициирует исходящие соединения.
resource "aws_security_group" "rds" {
  name   = "talk-booking-rds"
  vpc_id = module.vpc.vpc_id
}

# Источник — security group нод, а не диапазон адресов: ноды пересоздаются
# и меняют IP, принадлежность к группе остаётся.
resource "aws_vpc_security_group_ingress_rule" "rds_from_nodes" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = module.eks.node_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# Уникальный суффикс имени финального снимка: живёт и умирает вместе со стендом.
resource "random_id" "snapshot_suffix" {
  byte_length = 4
}

resource "aws_db_instance" "app" {
  identifier     = "talk-booking"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_encrypted = true

  db_name  = "talkbooking"
  username = "app"

  # Пароль ведёт сам RDS в Secrets Manager; обычный `password` попал бы в state.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.app.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Дефолт этого поля — 0, то есть автоматические бэкапы выключены.
  # 1 — потолок free-plan аккаунта: 7 отвергается FreeTierRestrictionError.
  backup_retention_period = 1

  # Комплект защит для стенда, который сносится в конце каждой сессии:
  # гейты выключены, чтобы destroy отрабатывал одной командой, но снимок
  # при удалении снимается всегда. См. docs/adr/19-rds-safety-flags.md
  deletion_protection       = false
  skip_final_snapshot       = false
  final_snapshot_identifier = "talk-booking-final-${random_id.snapshot_suffix.hex}"
}

output "rds_endpoint" {
  value = aws_db_instance.app.endpoint
}

output "rds_secret_arn" {
  description = "Secrets Manager ARN с master-паролем; понадобится в теме 21 (ESO)"
  value       = aws_db_instance.app.master_user_secret[0].secret_arn
}
