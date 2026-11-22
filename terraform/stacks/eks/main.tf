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

data "terraform_remote_state" "main" {
  backend = "local"
  config = {
    path = "${path.module}/../main/terraform.tfstate"
  }
}

locals {
  shared = data.terraform_remote_state.main.outputs.eks_shared
}

provider "aws" {
  region              = "ap-southeast-2"
  allowed_account_ids = [local.shared.account_id]

  default_tags {
    tags = {
      Project     = local.shared.project_name
      Environment = local.shared.environment
      ManagedBy   = "Terraform"
    }
  }
}

module "eks" {
  source = "../../modules/eks/cluster"

  cluster_name                   = local.shared.cluster_name
  cluster_version                = var.cluster_version
  cluster_role_arn               = local.shared.eks_cluster_role_arn
  fargate_pod_execution_role_arn = local.shared.fargate_pod_execution_role_arn
  codebuild_role_arn             = local.shared.codebuild_role_arn
  private_subnet_ids             = local.shared.private_subnet_ids
  cluster_public_access_cidrs    = var.cluster_admin_cidrs
  codebuild_security_group_id    = local.shared.codebuild_security_group_id
  function_role_arn              = local.shared.fargate_control_role_arn

  depends_on = [module.network]
}

module "network" {
  source = "../../modules/eks/network"

  project_name           = local.shared.project_name
  environment            = local.shared.environment
  public_subnet_id       = local.shared.public_subnet_ids[0]
  private_route_table_id = local.shared.private_route_table_id
}

module "observability" {
  source = "../../modules/eks/observability/iam"

  project_name    = local.shared.project_name
  oidc_issuer_url = module.eks.oidc_issuer_url
  bucket_arn      = local.shared.loki_bucket_arn
}

module "fargate_control_network" {
  count  = local.shared.enable_fargate_control ? 1 : 0
  source = "../../modules/eks/fargate-control/network"

  project_name              = local.shared.project_name
  vpc_id                    = local.shared.vpc_id
  cluster_security_group_id = module.eks.cluster_security_group_id
}

module "fargate_control" {
  count  = local.shared.enable_fargate_control ? 1 : 0
  source = "../../modules/eks/fargate-control/lambda"

  project_name       = local.shared.project_name
  cluster_name       = module.eks.cluster_name
  private_subnet_ids = local.shared.private_subnet_ids
  function_role_arn  = local.shared.fargate_control_role_arn
  security_group_id  = module.fargate_control_network[0].security_group_id

}

module "fargate_control_bus" {
  count  = local.shared.enable_fargate_control ? 1 : 0
  source = "../../modules/eks/fargate-control/eventbridge/control_bus"

  project_name  = local.shared.project_name
  function_name = module.fargate_control[0].function_name
  alias_arns = {
    stop    = module.fargate_control[0].stop_alias_arn
    restore = module.fargate_control[0].restore_alias_arn
  }
}

module "fargate_control_monitoring" {
  count  = local.shared.enable_fargate_control ? 1 : 0
  source = "../../modules/eks/fargate-control/cloudwatch/alarm"

  function_name    = module.fargate_control[0].function_name
  log_group_name   = local.shared.fargate_control_log_group_name
  sns_topic_arn    = local.shared.lambda_alerts_topic_arn
  event_bus_name   = module.fargate_control_bus[0].bus_name
  event_rule_names = module.fargate_control_bus[0].rule_names
}

module "fargate_control_schedule" {
  count  = local.shared.enable_fargate_control ? 1 : 0
  source = "../../modules/eks/fargate-control/eventbridge"

  project_name       = local.shared.project_name
  schedule_enabled   = var.enable_fargate_stop_schedule
  stop_alias_arn     = module.fargate_control[0].stop_alias_arn
  scheduler_role_arn = local.shared.fargate_scheduler_role_arn

  depends_on = [module.eks]
}
