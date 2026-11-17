resource "aws_eks_access_entry" "function" {
  cluster_name      = var.cluster_name
  principal_arn     = var.function_role_arn
  type              = "STANDARD"
  kubernetes_groups = ["fargate-control"]
}
