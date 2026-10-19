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

# Sensitive values come from a gitignored *.auto.tfvars file locally and from GitHub
# Actions secrets (TF_VAR_*) in CI. Marking them sensitive keeps them out of plan output,
# which in CI is visible in public workflow logs and PR comments.
variable "jenkins_allowed_cidr" {
  description = "CIDR allowed to reach the Jenkins UI on port 8080 (e.g. your public IP as x.x.x.x/32)"
  type        = string
  sensitive   = true

  validation {
    condition     = can(cidrnetmask(var.jenkins_allowed_cidr))
    error_message = "jenkins_allowed_cidr must be an IPv4 CIDR block, such as 203.0.113.10/32."
  }
}

variable "jenkins_instance_type" {
  description = "EC2 instance type for the Jenkins server"
  type        = string
  default     = "t3.medium"
}

variable "alert_email" {
  description = "Email address subscribed to the delivery alerts SNS topic"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}

variable "alb_5xx_alarm_threshold" {
  description = "Target 5XX responses within one minute that trigger the 5XX alarm"
  type        = number
  default     = 1
}
