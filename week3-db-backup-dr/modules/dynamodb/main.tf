resource "aws_kms_key" "dynamodb" {
  description             = "CMK for ${var.table_name} table encryption"
  deletion_window_in_days = 30
  # Some IAM-restricted sandbox accounts deny kms:EnableKeyRotation.
  enable_key_rotation = !var.restricted_permissions
}

resource "aws_kms_alias" "dynamodb" {
  name          = "alias/${var.table_name}-dynamodb"
  target_key_id = aws_kms_key.dynamodb.key_id
}

resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = var.hash_key
  range_key    = var.range_key

  attribute {
    name = var.hash_key
    type = "S"
  }

  attribute {
    name = var.range_key
    type = "S"
  }

  # Some IAM-restricted sandbox accounts deny dynamodb:UpdateTimeToLive.
  # Keeping the block (vs. omitting it) avoids forcing a destroy/recreate
  # of an already-existing table - only the "enabled" value changes.
  ttl {
    attribute_name = var.ttl_attribute
    enabled        = !var.restricted_permissions
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  # Disabled in restricted/sandbox mode so Terraform can actually replace
  # the table when needed (e.g. the ttl block changing); real accounts keep
  # this on.
  deletion_protection_enabled = !var.restricted_permissions
}

# Alert if the table is ever throttled (a signal to revisit capacity/keys
# even on PAY_PER_REQUEST, since hot partitions can still throttle).
resource "aws_cloudwatch_metric_alarm" "throttled_requests" {
  alarm_name          = "${var.table_name}-throttled-requests"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "DynamoDB requests are being throttled"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = aws_dynamodb_table.this.name
  }
}
