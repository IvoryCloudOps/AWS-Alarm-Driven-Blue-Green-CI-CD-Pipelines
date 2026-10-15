variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-east-2"
}


variable "bootstrap_image_tag" {
  description = "Image tag in ECR used by the initial task definition. Push this tag before the first full apply; the Jenkins pipeline deploys commit-SHA tags afterwards."
  type        = string
  default     = "bootstrap"
}
