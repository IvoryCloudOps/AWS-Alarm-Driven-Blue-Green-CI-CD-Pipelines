resource "aws_ecs_cluster" "delivery_cluster" {
  name = "blue-green-delivery-cluster"

  # Publishes RunningTaskCount and other service metrics used by the ECS alarm.
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Project   = "AWS Blue Green Container Delivery Platform"
    ManagedBy = "Terraform"
  }
}

resource "aws_cloudwatch_log_group" "application_logs" {
  name              = "/ecs/ivorycloud-delivery"
  retention_in_days = 7

  tags = {
    Project   = "AWS Blue Green Container Delivery Platform"
    ManagedBy = "Terraform"
  }
}

resource "aws_ecs_task_definition" "application" {
  family                   = "ivorycloud-delivery"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  cpu    = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "ivorycloud-delivery"
      essential = true

      image = "${aws_ecr_repository.app.repository_url}:${var.bootstrap_image_tag}"

      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"

        options = {
          awslogs-group         = aws_cloudwatch_log_group.application_logs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "application"
        }
      }
    }
  ])

  tags = {
    Project   = "AWS Blue Green Container Delivery Platform"
    ManagedBy = "Terraform"
  }
}

resource "aws_ecs_service" "application_service" {
  name            = "ivorycloud-delivery-service"
  cluster         = aws_ecs_cluster.delivery_cluster.id
  task_definition = aws_ecs_task_definition.application.arn

  desired_count = 1
  launch_type   = "FARGATE"

  # Long enough for an unhealthy target to stay registered for the two one-minute
  # periods the unhealthy-targets alarm needs before ECS replaces the task.
  health_check_grace_period_seconds = 240

  deployment_controller {
    type = "ECS"
  }

  deployment_configuration {
    strategy             = "BLUE_GREEN"
    bake_time_in_minutes = 5
  }

  # Roll back automatically when a new revision's targets go unhealthy.
  alarms {
    alarm_names = [aws_cloudwatch_metric_alarm.alb_unhealthy_targets.alarm_name]
    enable      = true
    rollback    = true
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets = [
      aws_subnet.private_a.id,
      aws_subnet.private_b.id
    ]

    security_groups = [
      aws_security_group.ecs_tasks_sg.id
    ]

    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue_tg.arn
    container_name   = "ivorycloud-delivery"
    container_port   = 8080

    advanced_configuration {
      alternate_target_group_arn = aws_lb_target_group.green_tg.arn
      production_listener_rule   = aws_lb_listener_rule.production_rule.arn
      role_arn                   = aws_iam_role.ecs_infrastructure_role.arn
    }
  }

  depends_on = [
    aws_lb_listener_rule.production_rule,
    aws_iam_role_policy_attachment.ecs_execution_policy,
    aws_iam_role_policy.ecs_infrastructure_policy
  ]

  # The Jenkins pipeline registers new task definition revisions and deploys them.
  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = {
    Project   = "AWS Blue Green Container Delivery Platform"
    ManagedBy = "Terraform"
  }
}