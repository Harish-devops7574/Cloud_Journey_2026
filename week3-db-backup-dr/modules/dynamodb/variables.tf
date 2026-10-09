variable "table_name" {
  type = string
}

variable "hash_key" {
  type = string
}

variable "range_key" {
  type = string
}

variable "ttl_attribute" {
  type = string
}

variable "sns_topic_arn" {
  type = string
}

variable "restricted_permissions" {
  description = "Set true for IAM-limited sandbox accounts; disables kms:EnableKeyRotation."
  type        = bool
  default     = false
}
