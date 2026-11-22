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

  project_name               = var.project_name
  cluster_name               = var.cluster_name
  fargate_log_group_arn      = module.fargate_logs.fargate_log_group_arn
  cloudwatch_log_group_arn   = module.cloudwatch.codebuild_log_group_arn
  github_connection_arn      = module.github_connection.arn
  ecr_repository_arn         = module.ecr.repository_arn
  build_tools_repository_arn = module.ecr.build_tools_repository_arn
  eks_cluster_arn            = local.cluster_arn
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

module "lambda_alerts" {
  count  = var.enable_fargate_control ? 1 : 0
  source = "../../modules/common/sns"

  project_name = var.project_name
}

module "ecr" {
  source = "../../modules/common/ecr"

  project_name = var.project_name
}

module "network" {
  source = "../../modules/common/network"

  project_name = var.project_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr
  cluster_name = var.cluster_name
}

module "loki_storage" {
  source = "../../modules/common/s3"

  project_name = var.project_name
}

module "github_connection" {
  source = "../../modules/common/github_connection"

  project_name = var.project_name
}

module "codebuild" {
  source = "../../modules/common/codebuild"

  project_name                = var.project_name
  aws_region                  = var.aws_region
  github_connection_arn       = module.github_connection.arn
  repository_branch           = var.website_repository_branch
  buildspec_path              = var.buildspec_path
  enable_github_webhook       = var.enable_github_webhook
  enable_weekly_report        = var.enable_weekly_report
  codebuild_role_arn          = module.iam.codebuild_role_arn
  vpc_id                      = module.network.vpc_id
  private_subnet_ids          = module.network.private_subnet_ids
  codebuild_security_group_id = module.network.codebuild_security_group_id
  ecr_repository_url          = module.ecr.repository_url
  eks_cluster_name            = var.cluster_name
  cloudwatch_log_group_name   = module.cloudwatch.codebuild_log_group_name
}
