output "replica_id" {
  value = aws_db_instance.replica.id
}

output "replica_endpoint" {
  value = aws_db_instance.replica.endpoint
}
