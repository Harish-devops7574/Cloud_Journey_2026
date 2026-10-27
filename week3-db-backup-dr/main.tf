# ---------------------------------------------------------------------------
# Shared SNS topic for all backup/DR/operational alarms
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-db-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count = var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ---------------------------------------------------------------------------
# Primary RDS MySQL instance
# ---------------------------------------------------------------------------

module "rds" {
  source = "./modules/rds"

  project_name = var.project_name
  environment  = var.environment

  vpc_id                 = var.vpc_id
  private_subnet_ids     = var.private_subnet_ids
  app_security_group_ids = var.app_security_group_ids

  engine_version        = var.db_engine_version
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage

  db_name         = var.db_name
  master_username = var.db_master_username

  backup_retention_period = var.db_backup_retention_period
  multi_az                = var.db_multi_az
  deletion_protection     = var.db_deletion_protection

  sns_topic_arn          = aws_sns_topic.alerts.arn
  restricted_permissions = var.restricted_permissions
}

# ---------------------------------------------------------------------------
# Cross-region DR read replica (opt-in via enable_cross_region_dr)
# ---------------------------------------------------------------------------

module "rds_dr_replica" {
  source = "./modules/rds_dr_replica"
  count  = var.enable_cross_region_dr ? 1 : 0

  providers = {
    aws = aws.dr
  }

  source_db_instance_arn = module.rds.db_instance_arn
  identifier             = "${var.project_name}-${var.environment}-db"
  instance_class         = var.db_instance_class
  kms_key_alias          = "${var.project_name}-${var.environment}-db-dr-replica"
  restricted_permissions = var.restricted_permissions
}

# ---------------------------------------------------------------------------
# DynamoDB table
# ---------------------------------------------------------------------------

module "dynamodb" {
  source = "./modules/dynamodb"

  table_name             = var.dynamodb_table_name
  hash_key               = var.dynamodb_hash_key
  range_key              = var.dynamodb_range_key
  ttl_attribute          = var.dynamodb_ttl_attribute
  sns_topic_arn          = aws_sns_topic.alerts.arn
  restricted_permissions = var.restricted_permissions
}

# ---------------------------------------------------------------------------
# Backup automation Lambda (on-demand RDS snapshot + DynamoDB backup, pruned
# on a schedule, independent of each service's own automated backups)
# ---------------------------------------------------------------------------

module "backup_automation" {
  source = "./modules/backup_automation"
  count  = var.enable_backup_automation ? 1 : 0

  providers = {
    aws          = aws
    aws.untagged = aws.untagged
  }

  project_name = var.project_name
  environment  = var.environment

  db_instance_identifier = module.rds.db_instance_id
  db_instance_arn        = module.rds.db_instance_arn

  dynamodb_table_name = module.dynamodb.table_name
  dynamodb_table_arn  = module.dynamodb.table_arn

  sns_topic_arn = aws_sns_topic.alerts.arn

  schedule_expression = var.backup_schedule_expression
  retention_days      = var.manual_snapshot_retention_days
  log_retention_days  = var.log_retention_days

  restricted_permissions = var.restricted_permissions
}

# ---------------------------------------------------------------------------
# AWS Backup — native, service-managed RDS snapshots (opt-in). This is the
# "native way to back up RDS" alternative to the custom Lambda above: no code
# to maintain, backups/restores are driven entirely by the AWS Backup console/
# API, and it's the standard mechanism for centralized backup policy across
# services. The Lambda in modules/backup_automation remains useful when you
# need custom pruning logic across RDS *and* DynamoDB in one place.
# ---------------------------------------------------------------------------

resource "aws_backup_vault" "this" {
  count = var.enable_aws_backup ? 1 : 0

  name        = "${var.project_name}-${var.environment}-backup-vault"
  kms_key_arn = module.rds.kms_key_arn
}

resource "aws_iam_role" "backup" {
  count = var.enable_aws_backup ? 1 : 0

  name = "${var.project_name}-${var.environment}-aws-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  count = var.enable_aws_backup ? 1 : 0

  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_plan" "this" {
  count = var.enable_aws_backup ? 1 : 0

  name = "${var.project_name}-${var.environment}-backup-plan"

  rule {
    rule_name         = "daily-rds-snapshot"
    target_vault_name = aws_backup_vault.this[0].name
    schedule          = var.aws_backup_schedule_expression

    lifecycle {
      delete_after = var.aws_backup_retention_days
    }
  }
}

resource "aws_backup_selection" "rds" {
  count = var.enable_aws_backup ? 1 : 0

  name         = "${var.project_name}-${var.environment}-rds-selection"
  plan_id      = aws_backup_plan.this[0].id
  iam_role_arn = aws_iam_role.backup[0].arn
  resources    = [module.rds.db_instance_arn]
}
