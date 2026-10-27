terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.40"
      configuration_aliases = [aws.dr]
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Uncomment and configure before first `terraform init` in a real account.
  # State is stored remotely with locking so multiple engineers can collaborate safely.
  # backend "s3" {
  #   bucket         = "REPLACE-ME-terraform-state-bucket"
  #   key            = "week3-db-backup-dr/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}
