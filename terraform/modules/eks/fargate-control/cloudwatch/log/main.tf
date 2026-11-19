resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.retention_in_days
}

resource "aws_cloudwatch_log_group" "fargate" {
  name              = "/aws/eks/${var.cluster_name}/fargate"
  retention_in_days = var.retention_in_days
}

resource "aws_cloudwatch_log_group" "fargate_destroy_function" {
  count             = var.enable_fargate_control ? 1 : 0
  name              = "/aws/lambda/${var.project_name}-fargate-control"
  retention_in_days = var.retention_in_days
}