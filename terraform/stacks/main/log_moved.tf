moved {
  from = module.cloudwatch.aws_cloudwatch_log_group.eks_cluster
  to   = module.fargate_logs.aws_cloudwatch_log_group.eks_cluster
}

moved {
  from = module.cloudwatch.aws_cloudwatch_log_group.fargate
  to   = module.fargate_logs.aws_cloudwatch_log_group.fargate
}

moved {
  from = module.cloudwatch.aws_cloudwatch_log_group.fargate_destroy_function
  to   = module.fargate_logs.aws_cloudwatch_log_group.fargate_destroy_function
}
