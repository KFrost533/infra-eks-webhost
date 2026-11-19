terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  cluster_arn = "arn:${data.aws_partition.current.partition}:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
}

module "cloudwatch" {
  source = "../../modules/common/cloudwatch/log"

  project_name = var.project_name
}

module "fargate_logs" {
  source = "../../modules/eks/fargate-control/cloudwatch/log"

  project_name           = var.project_name
  cluster_name           = var.cluster_name
  enable_fargate_control = var.enable_fargate_control
}

module "iam" {
  source = "../../modules/common/iam"

  project_name          = var.project_name
  cluster_name          = var.cluster_name
  fargate_log_group_arn = module.fargate_logs.fargate_log_group_arn
}

module "fargate_control_iam" {
  count  = var.enable_fargate_control ? 1 : 0
  source = "../../modules/eks/fargate-control/iam"

  project_name             = var.project_name
  cluster_name             = var.cluster_name
  cluster_arn              = local.cluster_arn
  github_oidc_provider_arn = module.iam.github_oidc_provider_arn
  github_repository        = trimsuffix(trimprefix(var.website_repository_url, "https://github.com/"), "/")
  stop_alias_arn           = "arn:${data.aws_partition.current.partition}:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-fargate-control:stop"
  control_bus_arn          = "arn:${data.aws_partition.current.partition}:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:event-bus/${var.project_name}-fargate-control"
}

module "codebuild_policy" {
  source = "../../modules/common/iam/codebuild"

  project_name               = var.project_name
  codebuild_role_name        = module.iam.codebuild_role_name
  cloudwatch_log_group_arn   = module.cloudwatch.codebuild_log_group_arn
  github_connection_arn      = module.github_connection.arn
  ecr_repository_arn         = module.ecr.repository_arn
  build_tools_repository_arn = module.ecr.build_tools_repository_arn
  eks_cluster_arn            = local.cluster_arn
}

module "lambda_alerts" {
  count  = var.enable_fargate_control ? 1 : 0
  source = "../../modules/common/sns"

  project_name = var.project_name
}

module "ecr" {
  source = "../../modules/common/ecr"

  project_name = var.project_name
}

module "github_connection" {
  source = "../../modules/common/github_connection"

  project_name = var.project_name
}
