output "invoke_urls" {
  value = { for k, s in aws_api_gateway_stage.stage : k => "${s.invoke_url}/users" }
}

output "api_key_id" {
  description = "Fetch the value: aws apigateway get-api-key --api-key <id> --include-value --query value --output text"
  value       = aws_api_gateway_api_key.test_client.id
}

output "api_key_value" {
  value     = aws_api_gateway_api_key.test_client.value
  sensitive = true
}
