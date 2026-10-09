output "db_endpoint" {
  description = "RDS primary instance connection endpoint."
  value       = module.rds.endpoint
}

output "db_instance_arn" {
  description = "ARN of the primary RDS instance (used to wire other services/modules)."
  value       = module.rds.db_instance_arn
}

output "db_master_user_secret_arn" {
  description = "Secrets Manager ARN holding the auto-generated RDS master password."
  value       = module.rds.master_user_secret_arn
  sensitive   = true
}

output "db_security_group_id" {
  description = "Security group attached to the RDS instance; grant app tier access via app_security_group_ids."
  value       = module.rds.security_group_id
}

output "dr_replica_endpoint" {
  description = "Cross-region DR replica endpoint (null unless enable_cross_region_dr = true)."
  value       = var.enable_cross_region_dr ? module.rds_dr_replica[0].replica_endpoint : null
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table."
  value       = module.dynamodb.table_name
}

output "dynamodb_table_arn" {
  value = module.dynamodb.table_arn
}

output "dynamodb_table_stream_arn" {
  value = module.dynamodb.table_stream_arn
}

output "backup_automation_function_name" {
  value = var.enable_backup_automation ? module.backup_automation[0].function_name : null
}

output "sns_topic_arn" {
  description = "Shared SNS topic ARN for backup/DR/operational alarms."
  value       = aws_sns_topic.alerts.arn
}

output "aws_backup_vault_name" {
  description = "AWS Backup vault holding native RDS recovery points (null unless enable_aws_backup = true)."
  value       = var.enable_aws_backup ? aws_backup_vault.this[0].name : null
}
