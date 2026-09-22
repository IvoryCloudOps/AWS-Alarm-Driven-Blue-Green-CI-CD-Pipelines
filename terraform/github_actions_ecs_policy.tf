data "aws_iam_role" "github_actions_role" {
  name = "GitHubActions-BlueGreenDelivery"
}

resource "aws_iam_role_policy" "github_actions_ecs_deploy" {
  name = "ECSDeployBlueGreenDelivery"
  role = data.aws_iam_role.github_actions_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:UpdateService"
        ]

        Resource = "*"
      },

      {
        Effect = "Allow"

        Action = [
          "iam:PassRole"
        ]

        Resource = [
          aws_iam_role.ecs_execution_role.arn
        ]
      }
    ]
  })
}