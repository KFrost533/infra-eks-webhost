mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }
  mock_data "aws_ssm_parameter" {
    defaults = {
      type  = "String"
      value = "https://github.com/KFrost533/infra-eks-webhost"
    }
  }
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["ap-southeast-2a", "ap-southeast-2b"]
    }
  }
}

run "shared_resources" {
  command = plan

  assert {
    condition     = output.eks_shared.account_id == "123456789012" && output.eks_shared.enable_fargate_control == false && output.eks_shared.codebuild_project_name == "infra-eks-webhost" && length(output.eks_shared.private_subnet_ids) > 0
    error_message = "The shared root must expose the account and Fargate control configuration."
  }
  assert {
    condition     = output.eks_shared.github_oidc_provider_arn == "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    error_message = "The existing GitHub OIDC provider must be exposed to the EKS stack."
  }
  assert {
    condition     = length(module.fargate_control_iam) == 0 && length(module.lambda_alerts) == 0
    error_message = "Optional Fargate control IAM and SNS must be disabled by default."
  }
  assert {
    condition     = local.cluster_arn == "arn:aws:eks:${var.aws_region}:123456789012:cluster/infra-eks-webhost" && output.eks_shared.cluster_name == "infra-eks-webhost"
    error_message = "The shared policy must target the EKS cluster ARN without creating the cluster."
  }
}

run "custom_cluster_name" {
  command = plan
  variables {
    cluster_name = "custom-cluster"
  }

  assert {
    condition     = output.eks_shared.cluster_name == "custom-cluster" && local.cluster_arn == "arn:aws:eks:${var.aws_region}:123456789012:cluster/custom-cluster"
    error_message = "The cluster name override must be shared with the EKS stack and IAM policy."
  }
}

run "shared_fargate_control" {
  command = plan
  variables {
    enable_fargate_control = true
  }

  assert {
    condition     = output.eks_shared.enable_fargate_control && output.eks_shared.fargate_control_log_group_name == "/aws/lambda/${var.project_name}-fargate-control"
    error_message = "The shared output must include the log group when Fargate control is enabled."
  }
  assert {
    condition     = length(module.fargate_control_iam) == 1 && length(module.lambda_alerts) == 1
    error_message = "Fargate control IAM and SNS must be in the shared stack."
  }
}

