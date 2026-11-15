output "aws_region" {
  description = "AWS region containing the infrastructure."
  value       = var.aws_region
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
  value       = module.ecr.repository_url
}

output "codebuild_project_name" {
  description = "CodeBuild project name."
  value       = module.codebuild.project_name
}

output "github_connection_arn" {
  description = "GitHub CodeConnections ARN; authorize it in the AWS Console after creation."
  value       = module.github_connection.arn
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
              region ${var.aws_region}
              log_group_name ${module.cloudwatch.fargate_log_group_name}
              log_stream_prefix fargate-
              auto_create_group false
        CONFIG
      }
    })
  ])
}