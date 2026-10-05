variable "aws_region" {
  description = "Primary AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "Secondary AWS region used for disaster recovery (cross-region snapshot copy / read replica)."
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Short project name used as a prefix for resource names and tags."
  type        = string
  default     = "webapp"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod). Drives sizing and safety defaults."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "owner" {
  description = "Team or individual accountable for these resources (used in tags)."
  type        = string
  default     = "platform-team"
}

variable "restricted_permissions" {
  description = "Set true for IAM-limited sandbox/lab accounts that deny kms:EnableKeyRotation, rds:CreateDBParameterGroup, logs:PutRetentionPolicy, and events:TagResource. Disables only those specific hardening features so the stack can still deploy; leave false for real accounts."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Networking (bring-your-own VPC — this project intentionally does not
# provision a VPC; databases must land in existing private subnets)
# ---------------------------------------------------------------------------

variable "vpc_id" {
  description = "Existing VPC ID that hosts the database tier."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs (at least 2, in different AZs) for the RDS subnet group."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "Provide at least two private subnets in different Availability Zones for RDS Multi-AZ support."
  }
}

variable "app_security_group_ids" {
  description = "Security group IDs of application/EC2/Lambda clients allowed to reach the database on its port."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# RDS
# ---------------------------------------------------------------------------

variable "db_engine_version" {
  description = "MySQL engine version for RDS."
  type        = string
  default     = "8.0.35"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Initial allocated storage (GiB) for RDS."
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Upper bound (GiB) for RDS storage autoscaling. Set to 0 to disable."
  type        = number
  default     = 100
}

variable "db_name" {
  description = "Initial database schema name created inside the RDS instance."
  type        = string
  default     = "webapp"
}

variable "db_master_username" {
  description = "Master username for the RDS instance. The password is managed by AWS (Secrets Manager), never stored in state."
  type        = string
  default     = "admin"
}

variable "db_backup_retention_period" {
  description = "Number of days automated RDS backups are retained (1-35)."
  type        = number
  default     = 7

  validation {
    condition     = var.db_backup_retention_period >= 1 && var.db_backup_retention_period <= 35
    error_message = "db_backup_retention_period must be between 1 and 35."
  }
}

variable "db_multi_az" {
  description = "Whether to deploy RDS in Multi-AZ for high availability. Recommended true for prod."
  type        = bool
  default     = false
}

variable "db_deletion_protection" {
  description = "Enable RDS deletion protection. Recommended true for prod."
  type        = bool
  default     = false
}

variable "enable_cross_region_dr" {
  description = "When true, provisions a cross-region encrypted RDS read replica in var.dr_region for disaster recovery."
  type        = bool
  default     = false
}

variable "enable_backup_automation" {
  description = "When false, skips the backup-automation Lambda module entirely. Set false for IAM-restricted sandbox accounts that deny iam:PutRolePolicy / iam:PassRole, which are required to create any Lambda with a custom execution role."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# DynamoDB
# ---------------------------------------------------------------------------

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table."
  type        = string
  default     = "UserSessions"
}

variable "dynamodb_hash_key" {
  description = "Partition key attribute name."
  type        = string
  default     = "userId"
}

variable "dynamodb_range_key" {
  description = "Sort key attribute name."
  type        = string
  default     = "sessionId"
}

variable "dynamodb_ttl_attribute" {
  description = "Attribute name used for DynamoDB TTL (epoch seconds)."
  type        = string
  default     = "expiresAt"
}

# ---------------------------------------------------------------------------
# Backup automation (Lambda + EventBridge)
# ---------------------------------------------------------------------------

variable "backup_schedule_expression" {
  description = "EventBridge schedule expression that triggers the backup Lambda."
  type        = string
  default     = "cron(0 3 * * ? *)" # 03:00 UTC daily
}

variable "manual_snapshot_retention_days" {
  description = "Retention window (days) for manual RDS snapshots / on-demand DynamoDB backups created by the automation Lambda. Independent of RDS's own automated backup retention."
  type        = number
  default     = 14
}

variable "notification_email" {
  description = "Email address subscribed to the SNS topic for backup success/failure notifications. Leave empty to skip the subscription."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention (days) for the Lambda function."
  type        = number
  default     = 30
}
