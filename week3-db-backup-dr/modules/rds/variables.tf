variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "app_security_group_ids" {
  type    = list(string)
  default = []
}

variable "engine_version" {
  type = string
}

variable "instance_class" {
  type = string
}

variable "allocated_storage" {
  type = number
}

variable "max_allocated_storage" {
  type = number
}

variable "db_name" {
  type = string
}

variable "master_username" {
  type = string
}

variable "backup_retention_period" {
  type = number
}

variable "multi_az" {
  type = bool
}

variable "deletion_protection" {
  type = bool
}

variable "sns_topic_arn" {
  description = "SNS topic used for RDS event subscription (failover, low storage, etc)."
  type        = string
}

variable "restricted_permissions" {
  description = "Set true for IAM-limited sandbox accounts; disables kms:EnableKeyRotation and skips the custom RDS parameter group (rds:CreateDBParameterGroup)."
  type        = bool
  default     = false
}
