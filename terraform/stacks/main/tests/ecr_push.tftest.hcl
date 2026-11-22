mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
  mock_data "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }
}

run "github_ecr_push" {
  command = plan
  module {
    source = "../../modules/common/iam"
  }
  variables {
    project_name               = "project"
    cluster_name               = "cluster"
    fargate_log_group_arn      = "arn:aws:logs:ap-southeast-2:123456789012:log-group:fargate"
    cloudwatch_log_group_arn   = "arn:aws:logs:ap-southeast-2:123456789012:log-group:codebuild"
    github_connection_arn      = "arn:aws:codeconnections:ap-southeast-2:123456789012:connection/test"
    ecr_repository_arn         = "arn:aws:ecr:ap-southeast-2:123456789012:repository/website"
    build_tools_repository_arn = "arn:aws:ecr:ap-southeast-2:123456789012:repository/build-tools"
    eks_cluster_arn            = "arn:aws:eks:ap-southeast-2:123456789012:cluster/cluster"
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.ecr_push.assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity" &&
      jsondecode(aws_iam_role.ecr_push.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com" &&
      jsondecode(aws_iam_role.ecr_push.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:KFrost533@155362696/infra-eks-webhost@1458593226:ref:refs/heads/main"
    )
    error_message = "The ECR push role must trust only the repository's main branch through GitHub OIDC."
  }
  assert {
    condition = anytrue([
      for statement in jsondecode(aws_iam_role_policy.ecr_push.policy).Statement :
      statement.Effect == "Allow" && statement.Resource == "*" && contains(statement.Action, "ecr:GetAuthorizationToken")
    ])
    error_message = "The ECR push role must be able to request an authorization token."
  }
}
