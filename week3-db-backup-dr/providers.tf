provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }
}

# Secondary region provider, only exercised when cross-region DR is enabled.
provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
      Purpose     = "disaster-recovery"
    }
  }
}

# Untagged alias: some locked-down sandbox accounts deny the TagResource call
# the provider issues for services that can't tag at create time (e.g.
# EventBridge). Used only for those specific resources when
# restricted_permissions = true; tags are unchanged for normal accounts.
provider "aws" {
  alias  = "untagged"
  region = var.aws_region

  default_tags {
    tags = var.restricted_permissions ? {} : {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }
}
