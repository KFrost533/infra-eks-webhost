mock_provider "aws" {}

run "loki_irsa" {
  command = plan
  module {
    source = "../../modules/eks/observability/iam"
  }
  variables {
    project_name    = "project"
    oidc_issuer_url = "https://oidc.eks.ap-southeast-2.amazonaws.com/id/example"
    bucket_arn      = "arn:aws:s3:::example-loki"
  }

  assert {
    condition     = contains(flatten([for statement in data.aws_iam_policy_document.loki_assume_role.statement : [for condition in statement.condition : condition.values]]), "system:serviceaccount:monitoring:loki")
    error_message = "The Loki role must trust only the monitoring/loki service account."
  }
  assert {
    condition     = toset([for statement in jsondecode(aws_iam_role_policy.loki.policy).Statement : statement.Resource]) == toset(["arn:aws:s3:::example-loki", "arn:aws:s3:::example-loki/*"])
    error_message = "Loki's S3 policy must be scoped to its bucket."
  }
}
