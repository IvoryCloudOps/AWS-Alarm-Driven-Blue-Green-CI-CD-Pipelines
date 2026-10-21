# One-time bootstrap for the S3 bucket that holds the main configuration's Terraform
# state. It has to exist before the main configuration can use the S3 backend, so it
# lives in its own configuration with local state. Apply it once, then leave it alone.

terraform {
  required_version = ">= 1.10.0"

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

variable "aws_region" {
  description = "AWS region for the state bucket"
  type        = string
  default     = "us-east-2"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "terraform_state" {
  # The account ID keeps the globally unique bucket name predictable.
  bucket = "blue-green-delivery-tfstate-${data.aws_caller_identity.current.account_id}"

  # Losing this bucket loses Terraform's record of every resource it manages.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name      = "blue-green-delivery-tfstate"
    Project   = "AWS Blue Green Container Delivery Platform"
    ManagedBy = "Terraform"
  }
}

# Every state write becomes a new version, so a bad apply or corrupted state can be
# recovered by restoring an earlier version.
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Disables ACLs so access is controlled only by IAM and the bucket policy.
resource "aws_s3_bucket_ownership_controls" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Old state versions are only needed for recovery, so expire them after 90 days.
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.terraform_state]
}

data "aws_iam_policy_document" "terraform_state" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  policy = data.aws_iam_policy_document.terraform_state.json

  depends_on = [aws_s3_bucket_public_access_block.terraform_state]
}

output "state_bucket_name" {
  description = "Bucket to use in the main configuration's backend block"
  value       = aws_s3_bucket.terraform_state.bucket
}
