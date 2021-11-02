variable "aws_region" {}
variable "tf_backend_bucket" {}

provider "aws" {
  region = var.aws_region
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> v1.0.4"
    }
  }
  ## Comment if using a local back to safe tf state file
  backend "s3" {
    bucket = var.tf_backend_bucket
    key    = "sdawsprdcr"
    region = var.aws_region
  }
  ## Uncomment if using a local back to safe tf state file
  # backend "local" {
  #   path = "relative/path/to/terraform.tfstate"
  # }
}
