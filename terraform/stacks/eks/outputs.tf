output "aws_region" {
  description = "AWS region containing the infrastructure."
  value       = local.shared.aws_region
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs for future internet-facing load balancers."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by EKS Fargate and CodeBuild."
  value       = module.network.private_subnet_ids
}

output "nat_gateway_public_ip" {
  description = "Public IPv4 address used for outbound traffic from Fargate."
  value       = module.network.nat_gateway_public_ip
}

output "eks_cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}

output "ecr_repository_url" {
  description = "ECR repository URL for website container images."
  value       = local.shared.ecr_repository_url
}

output "codebuild_project_name" {
  description = "CodeBuild project name."
  value       = module.codebuild.project_name
}

output "loki_role_arn" {
  description = "IAM role ARN for the monitoring/loki service account."
  value       = module.observability.loki_role_arn
}

output "github_connection_arn" {
  description = "GitHub CodeConnections ARN; authorize it in the AWS Console after creation."
  value       = local.shared.github_connection_arn
}

output "fargate_control_function_name" {
  description = "Function name for the Fargate stop/restore workflow."
  value       = try(module.fargate_control[0].function_name, null)

  precondition {
    condition = !local.shared.enable_fargate_control || alltrue([
      local.shared.fargate_control_log_group_name != null,
      local.shared.fargate_control_role_arn != null,
      local.shared.fargate_scheduler_role_arn != null,
      local.shared.fargate_restore_role_arn != null,
      local.shared.lambda_alerts_topic_arn != null,
    ])
    error_message = "Apply the main stack with Fargate control enabled before applying the EKS stack."
  }
}

output "fargate_restore_role_arn" {
  description = "GitHub Actions OIDC role ARN for requesting Fargate operations."
  value       = local.shared.fargate_restore_role_arn
}

output "fargate_control_bus_name" {
  description = "EventBridge bus used to request Fargate operations."
  value       = try(module.fargate_control_bus[0].bus_name, null)
}

output "lambda_alerts_topic_arn" {
  description = "SNS topic for Lambda alerts; configure and confirm an email subscription."
  value       = local.shared.lambda_alerts_topic_arn
}

output "ecr_endpoint_ids" {
  description = "VPC endpoint IDs used for private ECR access."
  value       = module.network.ecr_endpoint_ids
}

output "fargate_logging_manifest" {
  description = "Kubernetes manifest to configure the Fargate log router before deploying workloads."
  value = join("\n---\n", [
    yamlencode({
      apiVersion = "v1"
      kind       = "Namespace"
      metadata = {
        name   = "aws-observability"
        labels = { "aws-observability" = "enabled" }
      }
    }),
    yamlencode({
      apiVersion = "v1"
      kind       = "ConfigMap"
      metadata = {
        name      = "aws-logging"
        namespace = "aws-observability"
      }
      data = {
        "output.conf" = <<-CONFIG
          [OUTPUT]
              Name cloudwatch_logs
              Match kube.*
              region ${local.shared.aws_region}
              log_group_name ${local.shared.fargate_log_group_name}
              log_stream_prefix fargate-
              auto_create_group false
        CONFIG
      }
    })
  ])
}