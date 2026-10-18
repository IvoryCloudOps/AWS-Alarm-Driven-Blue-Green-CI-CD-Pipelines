resource "aws_sns_topic" "delivery_alerts" {
  name = "blue-green-delivery-alerts"

  tags = {
    Project   = "AWS Blue Green Container Delivery Platform"
    ManagedBy = "Terraform"
  }
}

# Email subscriptions stay "PendingConfirmation" until the link in the AWS email is clicked.
resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.delivery_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Alarm 1: any unhealthy target in either target group. ECS swaps which target group
# is live on every deployment, so both are watched by one alarm. The idle target
# group reports no data, which FILL treats as 0.
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_targets" {
  alarm_name          = "blue-green-alb-unhealthy-targets"
  alarm_description   = "One or more ALB targets in the blue or green target group are unhealthy."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.delivery_alerts.arn]
  ok_actions    = [aws_sns_topic.delivery_alerts.arn]

  metric_query {
    id          = "unhealthy"
    expression  = "MAX([FILL(blue, 0), FILL(green, 0)])"
    label       = "UnHealthyHostCount (blue or green)"
    return_data = true
  }

  metric_query {
    id = "blue"

    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "UnHealthyHostCount"
      period      = 60
      stat        = "Maximum"

      dimensions = {
        LoadBalancer = aws_lb.delivery_alb.arn_suffix
        TargetGroup  = aws_lb_target_group.blue_tg.arn_suffix
      }
    }
  }

  metric_query {
    id = "green"

    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "UnHealthyHostCount"
      period      = 60
      stat        = "Maximum"

      dimensions = {
        LoadBalancer = aws_lb.delivery_alb.arn_suffix
        TargetGroup  = aws_lb_target_group.green_tg.arn_suffix
      }
    }
  }

  tags = {
    Project   = "AWS Blue Green Container Delivery Platform"
    ManagedBy = "Terraform"
  }
}

# Alarm 2: the application itself returned 5XX responses through the ALB.
resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  alarm_name          = "blue-green-alb-target-5xx"
  alarm_description   = "The application returned HTTP 5XX responses through the ALB."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.alb_5xx_alarm_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.delivery_alb.arn_suffix
  }

  alarm_actions = [aws_sns_topic.delivery_alerts.arn]
  ok_actions    = [aws_sns_topic.delivery_alerts.arn]

  tags = {
    Project   = "AWS Blue Green Container Delivery Platform"
    ManagedBy = "Terraform"
  }
}

# Alarm 3: fewer running tasks than the service wants. RunningTaskCount comes from
# Container Insights, enabled on the cluster. Missing data is treated as breaching
# so the alarm also fires if the service stops reporting entirely.
resource "aws_cloudwatch_metric_alarm" "ecs_running_tasks_low" {
  alarm_name          = "blue-green-ecs-running-tasks-low"
  alarm_description   = "The ECS service is running fewer tasks than its desired count."
  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  comparison_operator = "LessThanThreshold"
  threshold           = aws_ecs_service.application_service.desired_count
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.delivery_cluster.name
    ServiceName = aws_ecs_service.application_service.name
  }

  alarm_actions = [aws_sns_topic.delivery_alerts.arn]
  ok_actions    = [aws_sns_topic.delivery_alerts.arn]

  tags = {
    Project   = "AWS Blue Green Container Delivery Platform"
    ManagedBy = "Terraform"
  }
}
