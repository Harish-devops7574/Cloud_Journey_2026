# Cross-region encrypted read replica. Promote it during a regional failover
# with: aws rds promote-read-replica --db-instance-identifier <this replica>

resource "aws_kms_key" "dr" {
  description             = "CMK for ${var.identifier} cross-region replica encryption"
  deletion_window_in_days = 30
  # Some IAM-restricted sandbox accounts deny kms:EnableKeyRotation.
  enable_key_rotation = !var.restricted_permissions
}

resource "aws_kms_alias" "dr" {
  name          = "alias/${var.kms_key_alias}"
  target_key_id = aws_kms_key.dr.key_id
}

resource "aws_db_instance" "replica" {
  identifier          = "${var.identifier}-dr-replica"
  instance_class      = var.instance_class
  replicate_source_db = var.source_db_instance_arn

  storage_encrypted = true
  kms_key_id        = aws_kms_key.dr.arn

  publicly_accessible     = false
  skip_final_snapshot     = true
  backup_retention_period = 7

  # Promote-to-primary readiness: keep automated backups running on the
  # replica itself so a promoted instance already has its own backup history.
}
