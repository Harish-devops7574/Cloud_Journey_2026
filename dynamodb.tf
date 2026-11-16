resource "aws_dynamodb_table" "users" {
  for_each = var.stages

  name         = each.value.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  # Protect real data from an accidental destroy in prod.
  deletion_protection_enabled = each.key == "prod"
}
