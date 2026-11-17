output "function_role_arn" {
  value      = aws_iam_role.function.arn
  depends_on = [aws_iam_role_policy_attachment.vpc, aws_iam_role_policy.eks]
}

output "scheduler_role_arn" {
  value = aws_iam_role.scheduler.arn
}

output "scheduler_role_id" {
  value = aws_iam_role.scheduler.id
}

output "github_restore_role_arn" {
  value = aws_iam_role.github_restore.arn
}

output "github_restore_role_id" {
  value = aws_iam_role.github_restore.id
}
