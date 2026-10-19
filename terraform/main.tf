terraform {
  # 1.10+ is required for S3 native state locking (use_lockfile).
  required_version = ">= 1.10.0"

  # The bucket is created by terraform/bootstrap. No credentials belong here: Terraform
  # uses the environment's credentials (an SSO session locally, OIDC in CI).
  backend "s3" {
    bucket       = "blue-green-delivery-tfstate-075723833258"
    key          = "blue-green-delivery/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.2"
    }
  }
}

provider "aws" {
  region = var.aws_region


}
