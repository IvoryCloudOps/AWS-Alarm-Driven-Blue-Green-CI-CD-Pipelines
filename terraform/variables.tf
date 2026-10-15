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

variable "jenkins_allowed_cidr" {
  description = "CIDR allowed to reach the Jenkins UI on port 8080 (e.g. your public IP as x.x.x.x/32)"
  type        = string
}

variable "jenkins_instance_type" {
  description = "EC2 instance type for the Jenkins server"
  type        = string
  default     = "t3.medium"
}
