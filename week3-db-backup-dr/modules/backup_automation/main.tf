locals {
  name = "${var.project_name}-${var.environment}-backup-automation"
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/backup_automation.py"
  output_path = "${path.module}/lambda_src/backup_automation.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name = "/aws/lambda/${local.name}"
  # Some IAM-restricted sandbox accounts deny logs:PutRetentionPolicy; leaving
  # this null skips that call (logs then never expire until manually managed).
  retention_in_days = var.restricted_permissions ? null : var.log_retention_days
}

# ---------------------------------------------------------------------------
# IAM role - least privilege, scoped to the specific RDS instance / DynamoDB
# table / SNS topic this Lambda manages (no wildcard resources).
# ---------------------------------------------------------------------------

resource "aws_iam_role" "lambda" {
  name = "${local.name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "${local.name}-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      },
      {
        Sid    = "RdsSnapshots"
        Effect = "Allow"
        Action = [
          "rds:CreateDBSnapshot",
          "rds:DescribeDBSnapshots",
          "rds:DeleteDBSnapshot",
        ]
        Resource = [
          var.db_instance_arn,
          "arn:aws:rds:*:*:snapshot:${var.db_instance_identifier}-manual-*",
        ]
      },
      {
        Sid    = "DynamoDbBackups"
        Effect = "Allow"
        Action = [
          "dynamodb:CreateBackup",
          "dynamodb:ListBackups",
          "dynamodb:DeleteBackup",
        ]
        Resource = [
          var.dynamodb_table_arn,
          "${var.dynamodb_table_arn}/backup/*",
        ]
      },
      {
        Sid      = "Notify"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = var.sns_topic_arn
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# Lambda function
# ---------------------------------------------------------------------------

resource "aws_lambda_function" "this" {
  function_name = local.name
  role          = aws_iam_role.lambda.arn
  handler       = "backup_automation.handler"
  runtime       = "python3.12"
  timeout       = 120

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      DB_INSTANCE_IDENTIFIER = var.db_instance_identifier
      DYNAMODB_TABLE_NAME    = var.dynamodb_table_name
      SNS_TOPIC_ARN          = var.sns_topic_arn
      RETENTION_DAYS         = var.retention_days
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}

# ---------------------------------------------------------------------------
# EventBridge schedule
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "schedule" {
  provider = aws.untagged

  name                = "${local.name}-schedule"
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "lambda" {
  provider = aws.untagged

  rule = aws_cloudwatch_event_rule.schedule.name
  arn  = aws_lambda_function.this.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}
