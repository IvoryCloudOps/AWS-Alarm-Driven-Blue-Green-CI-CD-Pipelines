output "ecr_repository_url" {
  description = "URL of the ECR repository for the application image"
  value       = aws_ecr_repository.app.repository_url
}


output "vpc_id" {
  description = "VPC ID for the delivery platform"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs used by the ALB"
  value = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by ECS/Fargate"
  value = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]
}

output "alb_dns_name" {
  value = aws_lb.delivery_alb.dns_name
}

output "blue_target_group_arn" {
  value = aws_lb_target_group.blue_tg.arn
}

output "green_target_group_arn" {
  value = aws_lb_target_group.green_tg.arn
}

output "production_listener_rule_arn" {
  value = aws_lb_listener_rule.production_rule.arn
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.delivery_cluster.name
}

output "ecs_service_name" {
  value = aws_ecs_service.application_service.name
}
output "jenkins_deploy_policy_arn" {
  description = "Attach this policy to the IAM role or user Jenkins uses"
  value       = aws_iam_policy.jenkins_deploy.arn
}

output "jenkins_instance_profile_name" {
  description = "Attach this instance profile to the Jenkins EC2 instance"
  value       = aws_iam_instance_profile.jenkins.name
}

output "jenkins_url" {
  description = "Jenkins UI URL"
  value       = "http://${aws_instance.jenkins.public_ip}:8080"
}

output "jenkins_instance_id" {
  value = aws_instance.jenkins.id
}

output "alerts_topic_arn" {
  description = "SNS topic that receives CloudWatch alarm notifications"
  value       = aws_sns_topic.delivery_alerts.arn
}
