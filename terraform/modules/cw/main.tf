resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.retention_in_days
}

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${var.project_name}"
  retention_in_days = var.retention_in_days
}

resource "aws_cloudwatch_log_group" "fargate" {
  name              = "/aws/eks/${var.cluster_name}/fargate"
  retention_in_days = var.retention_in_days
}