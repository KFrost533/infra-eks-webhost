output "aws_region" {
  description = "AWS region containing the infrastructure."
  value       = var.aws_region
}

output "ecr_repository_url" {
  description = "ECR repository URL for website container images."
  value       = module.ecr.repository_url
}

output "github_connection_arn" {
  description = "GitHub CodeConnections ARN; authorize it in the AWS Console after creation."
  value       = module.github_connection.arn
}

output "eks_shared" {
  description = "Shared resources required by the separately managed EKS stack."
  value = {
    account_id                     = data.aws_caller_identity.current.account_id
    aws_region                     = var.aws_region
    project_name                   = var.project_name
    environment                    = var.environment
    cluster_name                   = var.cluster_name
    website_repository_url         = var.website_repository_url
    enable_fargate_control         = var.enable_fargate_control
    eks_cluster_role_arn           = module.iam.eks_cluster_role_arn
    fargate_pod_execution_role_arn = module.iam.fargate_pod_execution_role_arn
    codebuild_role_arn             = module.iam.codebuild_role_arn
    codebuild_role_name            = module.iam.codebuild_role_name
    github_oidc_provider_arn       = module.iam.github_oidc_provider_arn
    codebuild_log_group_arn        = module.cloudwatch.codebuild_log_group_arn
    codebuild_log_group_name       = module.cloudwatch.codebuild_log_group_name
    fargate_log_group_name         = module.fargate_logs.fargate_log_group_name
    fargate_control_log_group_name = module.fargate_logs.fargate_control_log_group_name
    github_connection_arn          = module.github_connection.arn
    ecr_repository_arn             = module.ecr.repository_arn
    ecr_repository_url             = module.ecr.repository_url
    build_tools_repository_arn     = module.ecr.build_tools_repository_arn
    build_tools_repository_url     = module.ecr.build_tools_repository_url
    fargate_control_role_arn       = try(module.fargate_control_iam[0].function_role_arn, null)
    fargate_scheduler_role_arn     = try(module.fargate_control_iam[0].scheduler_role_arn, null)
    fargate_restore_role_arn       = try(module.fargate_control_iam[0].github_restore_role_arn, null)
    lambda_alerts_topic_arn        = try(module.lambda_alerts[0].topic_arn, null)
  }

}
