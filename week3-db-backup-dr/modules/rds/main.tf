locals {
  identifier = "${var.project_name}-${var.environment}-db"
  # Performance Insights requires at least a "medium" (or larger) burstable
  # instance class; micro/small classes reject CreateDBInstance outright.
  performance_insights_supported = !contains(["db.t3.micro", "db.t3.small", "db.t4g.micro", "db.t4g.small"], var.instance_class)
}

# ---------------------------------------------------------------------------
# KMS key dedicated to database encryption (storage + automated backups)
# ---------------------------------------------------------------------------

resource "aws_kms_key" "rds" {
  description             = "CMK for ${local.identifier} storage and snapshot encryption"
  deletion_window_in_days = 30
  # Some IAM-restricted sandbox accounts deny kms:EnableKeyRotation.
  enable_key_rotation = !var.restricted_permissions
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${local.identifier}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${local.identifier}-subnet-group"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "rds" {
  name        = "${local.identifier}-sg"
  description = "Allow MySQL access only from approved application security groups"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "ingress_mysql" {
  for_each = toset(var.app_security_group_ids)

  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = each.value
  description              = "MySQL from application tier"
}

# ---------------------------------------------------------------------------
# Parameter group (baseline hardening: require SSL/TLS connections).
# Skipped entirely if restricted_permissions = true, since some sandbox
# accounts deny rds:CreateDBParameterGroup outright; the instance then falls
# back to the engine's default parameter group (no enforced TLS).
# ---------------------------------------------------------------------------

resource "aws_db_parameter_group" "this" {
  count = var.restricted_permissions ? 0 : 1

  name   = "${local.identifier}-params"
  family = "mysql8.0"

  parameter {
    name         = "require_secure_transport"
    value        = "1"
    apply_method = "immediate"
  }
}

# ---------------------------------------------------------------------------
# RDS instance — password is generated and rotated by AWS (Secrets Manager),
# never written to Terraform state.
#
# Instance (not Aurora/Multi-AZ Cluster) by design: this workload's traffic
# doesn't justify Aurora's storage/compute cost premium, and standard RDS
# Multi-AZ (var.multi_az) already gives synchronous-standby HA + automatic
# failover, which is the specific HA property MySQL itself doesn't provide
# out of the box. Revisit Cluster mode only if read-replica autoscaling or
# sub-30s failover becomes a real requirement.
# ---------------------------------------------------------------------------

resource "aws_db_instance" "this" {
  identifier     = local.identifier
  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.rds.arn

  db_name  = var.db_name
  username = var.master_username

  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = var.restricted_permissions ? null : aws_db_parameter_group.this[0].name
  publicly_accessible    = false

  multi_az = var.multi_az

  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:30-sun:05:30"
  copy_tags_to_snapshot   = true

  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  # Performance Insights isn't supported on some small instance classes
  # (e.g. db.t3.micro) - skip it there instead of failing CreateDBInstance.
  performance_insights_enabled    = local.performance_insights_supported
  performance_insights_kms_key_id = local.performance_insights_supported ? aws_kms_key.rds.arn : null

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.identifier}-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }
}

# ---------------------------------------------------------------------------
# RDS event subscription -> SNS (failover, low storage, backup failures)
# ---------------------------------------------------------------------------

resource "aws_db_event_subscription" "this" {
  name        = "${local.identifier}-events"
  sns_topic   = var.sns_topic_arn
  source_type = "db-instance"
  # Event subscriptions key off the instance identifier, not aws_db_instance.id
  # (which is RDS's internal resource ID, e.g. "db-XXXX").
  source_ids = [aws_db_instance.this.identifier]

  event_categories = [
    "availability",
    "backup",
    "failover",
    "failure",
    "low storage",
    "maintenance",
    "recovery",
  ]
}

# ---------------------------------------------------------------------------
# CloudWatch alarms — baseline operational monitoring
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "free_storage_low" {
  alarm_name          = "${local.identifier}-free-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 2 * 1024 * 1024 * 1024 # 2 GiB
  alarm_description   = "RDS free storage below 2 GiB"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.id
  }
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${local.identifier}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU utilization above 80% for 15 minutes"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.id
  }
}
