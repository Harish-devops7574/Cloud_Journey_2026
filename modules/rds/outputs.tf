output "db_instance_id" {
  value = aws_db_instance.this.id
}

output "db_instance_arn" {
  value = aws_db_instance.this.arn
}

output "endpoint" {
  value = aws_db_instance.this.endpoint
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN holding the auto-generated master password."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "security_group_id" {
  value = aws_security_group.rds.id
}

output "kms_key_arn" {
  value = aws_kms_key.rds.arn
}
