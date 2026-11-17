terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region              = var.shared.aws_region
  allowed_account_ids = [var.shared.account_id]

  default_tags {
    tags = {
      Project     = var.shared.project_name
      Environment = var.shared.environment
      ManagedBy   = "Terraform"
    }
  }
}

module "network" {
  source = "../../modules/common/network"

  project_name = var.shared.project_name
  environment  = var.shared.environment
  vpc_cidr     = var.vpc_cidr
  cluster_name = var.shared.cluster_name
}

module "eks" {
  source = "../../modules/eks/cluster"

  cluster_name                   = var.shared.cluster_name
  cluster_version                = var.cluster_version
  cluster_role_arn               = var.shared.eks_cluster_role_arn
  fargate_pod_execution_role_arn = var.shared.fargate_pod_execution_role_arn
  codebuild_role_arn             = var.shared.codebuild_role_arn
  private_subnet_ids             = module.network.private_subnet_ids
  cluster_public_access_cidrs    = var.cluster_admin_cidrs
  codebuild_security_group_id    = module.network.codebuild_security_group_id
}

module "codebuild" {
  source = "../../modules/common/codebuild"

  project_name                = var.shared.project_name
  aws_region                  = var.shared.aws_region
  repository_url              = var.shared.website_repository_url
  github_connection_arn       = var.shared.github_connection_arn
  repository_branch           = var.website_repository_branch
  buildspec_path              = var.buildspec_path
  enable_github_webhook       = var.enable_github_webhook
  enable_weekly_report        = var.enable_weekly_report
  build_tools_repository_url  = var.shared.build_tools_repository_url
  build_tools_image_tag       = var.build_tools_image_tag
  codebuild_role_arn          = var.shared.codebuild_role_arn
  vpc_id                      = module.network.vpc_id
  private_subnet_ids          = module.network.private_subnet_ids
  codebuild_security_group_id = module.network.codebuild_security_group_id
  ecr_repository_url          = var.shared.ecr_repository_url
  eks_cluster_name            = module.eks.cluster_name
  cloudwatch_log_group_name   = var.shared.codebuild_log_group_name

  depends_on = [
    module.eks
  ]
}

module "fargate_control_network" {
  count  = var.shared.enable_fargate_control ? 1 : 0
  source = "../../modules/eks/fargate-control/network"

  project_name              = var.shared.project_name
  vpc_id                    = module.network.vpc_id
  cluster_security_group_id = module.eks.cluster_security_group_id
}

module "fargate_control_access" {
  count  = var.shared.enable_fargate_control ? 1 : 0
  source = "../../modules/eks/cluster/fargate_control"

  cluster_name      = module.eks.cluster_name
  function_role_arn = var.shared.fargate_control_role_arn
}

module "fargate_control" {
  count  = var.shared.enable_fargate_control ? 1 : 0
  source = "../../modules/eks/fargate-control/lambda"

  project_name       = var.shared.project_name
  cluster_name       = module.eks.cluster_name
  private_subnet_ids = module.network.private_subnet_ids
  function_role_arn  = var.shared.fargate_control_role_arn
  security_group_id  = module.fargate_control_network[0].security_group_id

}

module "fargate_control_bus" {
  count  = var.shared.enable_fargate_control ? 1 : 0
  source = "../../modules/eks/fargate-control/eventbridge/control_bus"

  project_name  = var.shared.project_name
  function_name = module.fargate_control[0].function_name
  alias_arns = {
    stop    = module.fargate_control[0].stop_alias_arn
    restore = module.fargate_control[0].restore_alias_arn
  }
}

module "fargate_control_monitoring" {
  count  = var.shared.enable_fargate_control ? 1 : 0
  source = "../../modules/alerts/lambda"

  function_name    = module.fargate_control[0].function_name
  log_group_name   = var.shared.fargate_control_log_group_name
  failure_pattern  = "\"FARGATE_CONTROL_FAILURE\""
  sns_topic_arn    = var.shared.lambda_alerts_topic_arn
  event_bus_name   = module.fargate_control_bus[0].bus_name
  event_rule_names = module.fargate_control_bus[0].rule_names
}

module "fargate_control_schedule" {
  count  = var.shared.enable_fargate_control ? 1 : 0
  source = "../../modules/eks/fargate-control/eventbridge"

  project_name       = var.shared.project_name
  schedule_enabled   = var.enable_fargate_stop_schedule
  stop_alias_arn     = module.fargate_control[0].stop_alias_arn
  scheduler_role_arn = var.shared.fargate_scheduler_role_arn

  depends_on = [module.fargate_control_access]
}
