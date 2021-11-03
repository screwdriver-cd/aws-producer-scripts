terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
  ## UnComment if using s3 backend to save tf state file
  # backend "s3" {
  #   bucket = tf_backend_bucket
  #   key    = "sdawsprdcr"
  #   region = aws_region
  # }
}
provider "aws" {}

