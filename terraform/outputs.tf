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