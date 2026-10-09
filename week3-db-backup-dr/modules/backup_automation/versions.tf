terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.untagged]
    }
    archive = {
      source = "hashicorp/archive"
    }
  }
}
