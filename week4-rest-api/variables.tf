variable "region" {
  type    = string
  default = "us-east-1"
}

# "-tf" suffix so this stack never collides with the console/CLI-built resources.
variable "name" {
  description = "Base name for all resources"
  type        = string
  default     = "users-api-tf"
}

variable "allowed_origin" {
  description = "Value for Access-Control-Allow-Origin. Restrict in real prod."
  type        = string
  default     = "*"
}

# One entry per stage. Each stage gets its own table, Lambda alias and throttle.
variable "stages" {
  type = map(object({
    table_name      = string
    lambda_alias    = string
    rate_limit      = number
    burst_limit     = number
    alias_to_latest = bool # dev tracks $LATEST, prod is pinned to the published version
  }))
  default = {
    dev = {
      table_name      = "Users-dev-tf"
      lambda_alias    = "dev"
      rate_limit      = 50
      burst_limit     = 100
      alias_to_latest = true
    }
    prod = {
      table_name      = "Users-tf"
      lambda_alias    = "prod"
      rate_limit      = 50
      burst_limit     = 100
      alias_to_latest = false
    }
  }
}

variable "usage_plan" {
  type = object({
    rate_limit  = number
    burst_limit = number
    quota_limit = number
  })
  default = {
    rate_limit  = 20
    burst_limit = 40
    quota_limit = 1000
  }
}

variable "log_retention_days" {
  type    = number
  default = 14
}
