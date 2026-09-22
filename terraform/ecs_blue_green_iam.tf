resource "aws_iam_role" "ecs_infrastructure_role" {
  name = "blue-green-ecs-infrastructure-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ecs.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project   = "AWS Blue Green Container Delivery Platform"
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_role_policy" "ecs_infrastructure_policy" {
  name = "blue-green-ecs-load-balancer-management"
  role = aws_iam_role.ecs_infrastructure_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:ModifyListener"
        ]

        Resource = "*"
      }
    ]
  })
}