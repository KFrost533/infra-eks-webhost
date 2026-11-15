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

module "network" {
  source = "../modules/network"

  project_name = var.project_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr
  cluster_name = var.cluster_name
}

module "cloudwatch" {
  source = "../modules/cw"

  project_name = var.project_name
  cluster_name = var.cluster_name
}

module "iam" {
  source = "../modules/iam"

  project_name          = var.project_name
  cluster_name          = var.cluster_name
  fargate_log_group_arn = module.cloudwatch.fargate_log_group_arn
}

module "ecr" {
  source = "../modules/ecr"

  project_name = var.project_name
}

module "github_connection" {
  source = "../modules/github_connection"

  project_name = var.project_name
}

module "eks" {
  source = "../modules/eks"

  cluster_name                   = var.cluster_name
  cluster_version                = var.cluster_version
  cluster_role_arn               = module.iam.eks_cluster_role_arn
  fargate_pod_execution_role_arn = module.iam.fargate_pod_execution_role_arn
  codebuild_role_arn             = module.iam.codebuild_role_arn
  private_subnet_ids             = module.network.private_subnet_ids
  cluster_public_access_cidrs    = var.cluster_admin_cidrs
  codebuild_security_group_id    = module.network.codebuild_security_group_id
  depends_on = [
    module.cloudwatch,
    module.iam
  ]
}

module "codebuild_policy" {
  source = "../modules/iam/codebuild_policy"

  project_name               = var.project_name
  codebuild_role_name        = module.iam.codebuild_role_name
  cloudwatch_log_group_arn   = module.cloudwatch.codebuild_log_group_arn
  github_connection_arn      = module.github_connection.arn
  ecr_repository_arn         = module.ecr.repository_arn
  build_tools_repository_arn = module.ecr.build_tools_repository_arn
  eks_cluster_arn            = module.eks.cluster_arn
}

module "codebuild" {
  source = "../modules/codebuild"

  project_name                = var.project_name
  aws_region                  = var.aws_region
  repository_url              = var.website_repository_url
  github_connection_arn       = module.github_connection.arn
  repository_branch           = var.website_repository_branch
  buildspec_path              = var.buildspec_path
  enable_github_webhook       = var.enable_github_webhook
  enable_weekly_report        = var.enable_weekly_report
  build_tools_repository_url  = module.ecr.build_tools_repository_url
  build_tools_image_tag       = var.build_tools_image_tag
  codebuild_role_arn          = module.iam.codebuild_role_arn
  vpc_id                      = module.network.vpc_id
  private_subnet_ids          = module.network.private_subnet_ids
  codebuild_security_group_id = module.network.codebuild_security_group_id
  ecr_repository_url          = module.ecr.repository_url
  eks_cluster_name            = module.eks.cluster_name
  cloudwatch_log_group_name   = module.cloudwatch.codebuild_log_group_name

  depends_on = [
    module.eks,
    module.codebuild_policy
  ]
}
