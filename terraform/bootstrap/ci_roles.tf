# IAM roles for the GitHub Actions infrastructure pipeline. They live in this bootstrap
# configuration, which is applied locally by an administrator, so the pipeline can never
# change its own permissions. The app deploy role (GitHubActions-BlueGreenDelivery) is
# separate and untouched.
#
#   GitHubActions-Terraform-Plan  - read-only. Used by pull requests and by main.
#   GitHubActions-Terraform-Apply - can change this project's resources. Only jobs that
#                                   run in the protected "production" GitHub environment.
#
# Neither role name matches the IAM patterns the apply role may manage (blue-green-*,
# GitHubActions-BlueGreenDelivery), so the apply role cannot modify itself or the plan role.

variable "github_repository" {
  description = "GitHub repository (owner/name) allowed to assume the Terraform CI roles"
  type        = string
  default     = "IvoryCloudOps/aws-blue-green-delivery-platform"
}

variable "github_apply_environment" {
  description = "GitHub Actions environment whose jobs may assume the apply role"
  type        = string
  default     = "production"
}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  state_key   = "blue-green-delivery/terraform.tfstate"
  project_tag = "AWS Blue Green Container Delivery Platform"

  # The roles, policy, and instance profile the main configuration manages.
  managed_role_arns = [
    "arn:aws:iam::${local.account_id}:role/blue-green-*",
    "arn:aws:iam::${local.account_id}:role/GitHubActions-BlueGreenDelivery",
  ]

  # The only managed policies the main configuration attaches to its roles.
  attachable_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    "arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::${local.account_id}:policy/JenkinsBlueGreenDelivery",
  ]
}

# Created outside Terraform before this project; referenced, not managed.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# ---------------------------------------------------------------------------
# Trust policies
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "plan_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Pull requests in this repository (GitHub does not issue OIDC tokens to fork PRs)
    # and runs on main, such as a drift check.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repository}:pull_request",
        "repo:${var.github_repository}:ref:refs/heads/main",
      ]
    }
  }
}

data "aws_iam_policy_document" "apply_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only jobs in the protected environment, which requires a reviewer's approval.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:environment:${var.github_apply_environment}"]
    }
  }
}

# ---------------------------------------------------------------------------
# Permissions shared by both roles: state access and read-only refresh
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "terraform_read" {
  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.terraform_state.arn]
  }

  statement {
    sid       = "ReadState"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.terraform_state.arn}/${local.state_key}"]
  }

  # Plans lock state too, so both roles can create and remove the lock file, but only
  # the apply role can write the state itself.
  statement {
    sid       = "ManageStateLock"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.terraform_state.arn}/${local.state_key}.tflock"]
  }

  statement {
    sid    = "ReadRegionalResources"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "elasticloadbalancing:Describe*",
      "ecs:Describe*",
      "ecs:List*",
      "ecr:DescribeRepositories",
      "ecr:GetLifecyclePolicy",
      "ecr:GetRepositoryPolicy",
      "ecr:ListTagsForResource",
      "logs:DescribeLogGroups",
      "logs:ListTagsForResource",
      "logs:ListTagsLogGroup",
      "sns:GetTopicAttributes",
      "sns:GetSubscriptionAttributes",
      "sns:GetDataProtectionPolicy",
      "sns:ListSubscriptionsByTopic",
      "sns:ListTagsForResource",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListTagsForResource",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid       = "ReadAmiParameter"
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:aws:ssm:${var.aws_region}::parameter/aws/service/ami-amazon-linux-latest/*"]
  }

  statement {
    sid    = "ReadIam"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:GetInstanceProfile",
      "iam:ListRoleTags",
      "iam:ListPolicyTags",
      "iam:ListInstanceProfileTags",
    ]
    resources = ["*"]
  }
}

# ---------------------------------------------------------------------------
# Additional permissions for the apply role, limited to what this project manages
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "terraform_write" {
  statement {
    sid       = "WriteState"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.terraform_state.arn}/${local.state_key}"]
  }

  statement {
    sid    = "ManageNetworkingAndJenkinsHost"
    effect = "Allow"
    actions = [
      "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
      "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
      "ec2:AllocateAddress", "ec2:ReleaseAddress", "ec2:AssociateAddress", "ec2:DisassociateAddress",
      "ec2:CreateNatGateway", "ec2:DeleteNatGateway",
      "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:CreateRoute", "ec2:DeleteRoute",
      "ec2:ReplaceRoute", "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
      "ec2:ReplaceRouteTableAssociation",
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress", "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
      "ec2:RunInstances", "ec2:TerminateInstances", "ec2:StartInstances", "ec2:StopInstances",
      "ec2:ModifyInstanceAttribute", "ec2:ModifyInstanceMetadataOptions",
      "ec2:ModifyInstanceMaintenanceOptions", "ec2:ModifyInstanceCreditSpecification",
      "ec2:ModifyVolume",
      "ec2:AssociateIamInstanceProfile", "ec2:DisassociateIamInstanceProfile",
      "ec2:ReplaceIamInstanceProfileAssociation",
      "ec2:CreateTags", "ec2:DeleteTags",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid    = "ManageLoadBalancing"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetSecurityGroups", "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:CreateTargetGroup", "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:ModifyTargetGroup", "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:CreateListener", "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:ModifyListener", "elasticloadbalancing:ModifyListenerAttributes",
      "elasticloadbalancing:CreateRule", "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:ModifyRule", "elasticloadbalancing:SetRulePriorities",
      "elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid    = "ManageEcs"
    effect = "Allow"
    actions = [
      "ecs:CreateCluster", "ecs:DeleteCluster", "ecs:UpdateCluster", "ecs:UpdateClusterSettings",
      "ecs:PutClusterCapacityProviders",
      "ecs:RegisterTaskDefinition", "ecs:DeregisterTaskDefinition", "ecs:DeleteTaskDefinitions",
      "ecs:CreateService", "ecs:UpdateService", "ecs:DeleteService",
      "ecs:TagResource", "ecs:UntagResource",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid    = "ManageEcrRepository"
    effect = "Allow"
    actions = [
      "ecr:CreateRepository", "ecr:DeleteRepository",
      "ecr:PutImageTagMutability", "ecr:PutImageScanningConfiguration",
      "ecr:PutLifecyclePolicy", "ecr:DeleteLifecyclePolicy",
      "ecr:SetRepositoryPolicy", "ecr:DeleteRepositoryPolicy",
      "ecr:TagResource", "ecr:UntagResource",
    ]
    resources = ["arn:aws:ecr:${var.aws_region}:${local.account_id}:repository/ivorycloud-delivery"]
  }

  statement {
    sid    = "ManageApplicationLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup", "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy",
      "logs:TagResource", "logs:UntagResource", "logs:TagLogGroup", "logs:UntagLogGroup",
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/ecs/ivorycloud-delivery*"]
  }

  statement {
    sid    = "ManageAlertsTopic"
    effect = "Allow"
    actions = [
      "sns:CreateTopic", "sns:DeleteTopic", "sns:SetTopicAttributes",
      "sns:Subscribe", "sns:TagResource", "sns:UntagResource",
    ]
    resources = ["arn:aws:sns:${var.aws_region}:${local.account_id}:blue-green-delivery-alerts"]
  }

  # Subscription actions do not support resource ARNs in IAM, so they need "*".
  statement {
    sid       = "ManageAlertSubscriptions"
    effect    = "Allow"
    actions   = ["sns:Unsubscribe", "sns:SetSubscriptionAttributes"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid    = "ManageAlarms"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms",
      "cloudwatch:TagResource", "cloudwatch:UntagResource",
    ]
    resources = ["arn:aws:cloudwatch:${var.aws_region}:${local.account_id}:alarm:blue-green-*"]
  }

  statement {
    sid    = "ManageProjectRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy",
      "iam:TagRole", "iam:UntagRole",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy",
    ]
    resources = local.managed_role_arns
  }

  # Managed policy attachments are limited to the policies the project actually uses,
  # so the apply role cannot attach something like AdministratorAccess.
  statement {
    sid       = "AttachApprovedPolicies"
    effect    = "Allow"
    actions   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
    resources = local.managed_role_arns

    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = local.attachable_policy_arns
    }
  }

  statement {
    sid    = "ManageJenkinsDeployPolicy"
    effect = "Allow"
    actions = [
      "iam:CreatePolicy", "iam:DeletePolicy",
      "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:SetDefaultPolicyVersion",
      "iam:TagPolicy", "iam:UntagPolicy",
    ]
    resources = ["arn:aws:iam::${local.account_id}:policy/JenkinsBlueGreenDelivery"]
  }

  statement {
    sid    = "ManageJenkinsInstanceProfile"
    effect = "Allow"
    actions = [
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile", "iam:UntagInstanceProfile",
    ]
    resources = ["arn:aws:iam::${local.account_id}:instance-profile/blue-green-*"]
  }

  statement {
    sid       = "PassProjectRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/blue-green-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com", "ecs.amazonaws.com", "ec2.amazonaws.com"]
    }
  }

  statement {
    sid       = "CreateServiceLinkedRoles"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["ecs.amazonaws.com", "elasticloadbalancing.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "terraform_apply" {
  source_policy_documents = [
    data.aws_iam_policy_document.terraform_read.json,
    data.aws_iam_policy_document.terraform_write.json,
  ]
}

# ---------------------------------------------------------------------------
# Roles
# ---------------------------------------------------------------------------

resource "aws_iam_role" "terraform_plan" {
  name                 = "GitHubActions-Terraform-Plan"
  description          = "GitHub Actions: read-only Terraform plan for ${var.github_repository}"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600

  tags = {
    Project   = local.project_tag
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_role_policy" "terraform_plan" {
  name   = "TerraformPlan"
  role   = aws_iam_role.terraform_plan.id
  policy = data.aws_iam_policy_document.terraform_read.json
}

resource "aws_iam_role" "terraform_apply" {
  name                 = "GitHubActions-Terraform-Apply"
  description          = "GitHub Actions: Terraform apply for ${var.github_repository}, ${var.github_apply_environment} environment only"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600

  tags = {
    Project   = local.project_tag
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_role_policy" "terraform_apply" {
  name   = "TerraformApply"
  role   = aws_iam_role.terraform_apply.id
  policy = data.aws_iam_policy_document.terraform_apply.json
}

output "terraform_plan_role_arn" {
  description = "Role for the PR plan workflow (role-to-assume)"
  value       = aws_iam_role.terraform_plan.arn
}

output "terraform_apply_role_arn" {
  description = "Role for the apply workflow (role-to-assume, production environment)"
  value       = aws_iam_role.terraform_apply.arn
}
