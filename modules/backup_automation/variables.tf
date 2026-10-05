variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "db_instance_identifier" {
  description = "Identifier of the RDS instance to snapshot (not the ARN)."
  type        = string
}

variable "db_instance_arn" {
  description = "ARN of the RDS instance, used to scope the Lambda's IAM policy."
  type        = string
}

variable "dynamodb_table_name" {
  type = string
}

variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table, used to scope the Lambda's IAM policy."
  type        = string
}

variable "sns_topic_arn" {
  type = string
}

variable "schedule_expression" {
  description = "EventBridge schedule expression that triggers the backup Lambda."
  type        = string
}

variable "retention_days" {
  description = "Retention window (days) for the manual snapshots/backups this Lambda creates."
  type        = number
}

variable "log_retention_days" {
  type = number
}

variable "restricted_permissions" {
  description = "Set true for IAM-limited sandbox accounts; skips logs:PutRetentionPolicy."
  type        = bool
  default     = false
}
