output "cluster_name" {
  description = "EKS cluster name."
  value       = var.cluster_name
}


output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "EKS Kubernetes API endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_security_group_id" {
  description = "Security group attached to the EKS control plane."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for IAM roles for service accounts."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}