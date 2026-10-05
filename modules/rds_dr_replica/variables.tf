variable "source_db_instance_arn" {
  type = string
}

variable "identifier" {
  type = string
}

variable "instance_class" {
  type = string
}

variable "kms_key_alias" {
  description = "Alias for the DR-region KMS key used to encrypt the cross-region replica."
  type        = string
}

variable "restricted_permissions" {
  description = "Set true for IAM-limited sandbox accounts; disables kms:EnableKeyRotation."
  type        = bool
  default     = false
}
