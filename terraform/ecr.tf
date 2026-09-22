resource "aws_ecr_repository" "app" {
  name                 = "ivorycloud-delivery"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project   = "AWS Blue Green Container Delivery Platform"
    ManagedBy = "terraform"
  }
}
