locals {
  # method key => { resource, verb }. Adding an endpoint is one line here.
  methods = {
    list_users  = { resource = "users", verb = "GET" }
    create_user = { resource = "users", verb = "POST" }
    get_user    = { resource = "user", verb = "GET" }
    update_user = { resource = "user", verb = "PUT" }
    delete_user = { resource = "user", verb = "DELETE" }
  }

  resource_ids = {
    users = aws_api_gateway_resource.users.id
    user  = aws_api_gateway_resource.user.id
  }

  cors_headers = {
    "Access-Control-Allow-Origin"  = "'${var.allowed_origin}'"
    "Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Api-Key'"
    "Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
  }

  # Alias is resolved per stage through the stage variable, so one integration serves dev and prod.
  integration_uri = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.users.arn}:$${stageVariables.lambdaAlias}/invocations"
}

resource "aws_api_gateway_rest_api" "users" {
  name = var.name

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "users" {
  rest_api_id = aws_api_gateway_rest_api.users.id
  parent_id   = aws_api_gateway_rest_api.users.root_resource_id
  path_part   = "users"
}

resource "aws_api_gateway_resource" "user" {
  rest_api_id = aws_api_gateway_rest_api.users.id
  parent_id   = aws_api_gateway_resource.users.id
  path_part   = "{id}"
}

# ---- CRUD methods with Lambda proxy integration ----

resource "aws_api_gateway_method" "crud" {
  for_each = local.methods

  rest_api_id      = aws_api_gateway_rest_api.users.id
  resource_id      = local.resource_ids[each.value.resource]
  http_method      = each.value.verb
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "crud" {
  for_each = local.methods

  rest_api_id             = aws_api_gateway_rest_api.users.id
  resource_id             = local.resource_ids[each.value.resource]
  http_method             = aws_api_gateway_method.crud[each.key].http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST" # Lambda is always invoked with POST
  uri                     = local.integration_uri
}

# ---- CORS preflight (OPTIONS, MOCK, no API key) ----

resource "aws_api_gateway_method" "options" {
  for_each = local.resource_ids

  rest_api_id      = aws_api_gateway_rest_api.users.id
  resource_id      = each.value
  http_method      = "OPTIONS"
  authorization    = "NONE"
  api_key_required = false
}

resource "aws_api_gateway_integration" "options" {
  for_each = local.resource_ids

  rest_api_id = aws_api_gateway_rest_api.users.id
  resource_id = each.value
  http_method = aws_api_gateway_method.options[each.key].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }
}

resource "aws_api_gateway_method_response" "options" {
  for_each = local.resource_ids

  rest_api_id = aws_api_gateway_rest_api.users.id
  resource_id = each.value
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = "200"

  response_parameters = { for h, _ in local.cors_headers : "method.response.header.${h}" => true }
}

resource "aws_api_gateway_integration_response" "options" {
  for_each = local.resource_ids

  rest_api_id = aws_api_gateway_rest_api.users.id
  resource_id = each.value
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = aws_api_gateway_method_response.options[each.key].status_code

  response_parameters = { for h, v in local.cors_headers : "method.response.header.${h}" => v }

  depends_on = [aws_api_gateway_integration.options]
}

# CORS headers on gateway-generated errors (403 missing key, 429 throttled, 5XX).
resource "aws_api_gateway_gateway_response" "cors" {
  for_each = toset(["DEFAULT_4XX", "DEFAULT_5XX"])

  rest_api_id   = aws_api_gateway_rest_api.users.id
  response_type = each.key

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin"  = "'${var.allowed_origin}'"
    "gatewayresponse.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Api-Key'"
  }
}

# ---- Deployment and stages ----

resource "aws_api_gateway_deployment" "users" {
  rest_api_id = aws_api_gateway_rest_api.users.id

  # Terraform does not redeploy on its own when methods/integrations change; this hash forces it.
  triggers = {
    redeploy = sha1(jsonencode([
      local.methods,
      local.integration_uri,
      local.cors_headers,
      aws_api_gateway_resource.users.id,
      aws_api_gateway_resource.user.id,
      [for m in aws_api_gateway_method.crud : m.id],
      [for i in aws_api_gateway_integration.crud : i.id],
      [for i in aws_api_gateway_integration_response.options : i.id],
      [for g in aws_api_gateway_gateway_response.cors : g.id],
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.crud,
    aws_api_gateway_integration_response.options,
  ]
}

resource "aws_api_gateway_stage" "stage" {
  for_each = var.stages

  rest_api_id   = aws_api_gateway_rest_api.users.id
  deployment_id = aws_api_gateway_deployment.users.id
  stage_name    = each.key

  variables = {
    lambdaAlias = each.value.lambda_alias
    tableName   = each.value.table_name
  }

  depends_on = [aws_lambda_permission.apigw]
}

resource "aws_api_gateway_method_settings" "all" {
  for_each = var.stages

  rest_api_id = aws_api_gateway_rest_api.users.id
  stage_name  = aws_api_gateway_stage.stage[each.key].stage_name
  method_path = "*/*"

  settings {
    throttling_rate_limit  = each.value.rate_limit
    throttling_burst_limit = each.value.burst_limit
    metrics_enabled        = true
  }
}

# ---- API key + usage plan ----

resource "aws_api_gateway_usage_plan" "basic" {
  name = "${var.name}-basic"

  dynamic "api_stages" {
    for_each = aws_api_gateway_stage.stage
    content {
      api_id = aws_api_gateway_rest_api.users.id
      stage  = api_stages.value.stage_name
    }
  }

  throttle_settings {
    rate_limit  = var.usage_plan.rate_limit
    burst_limit = var.usage_plan.burst_limit
  }

  quota_settings {
    limit  = var.usage_plan.quota_limit
    period = "MONTH"
  }
}

resource "aws_api_gateway_api_key" "test_client" {
  name = "${var.name}-test-client"
}

resource "aws_api_gateway_usage_plan_key" "test_client" {
  key_id        = aws_api_gateway_api_key.test_client.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.basic.id
}
