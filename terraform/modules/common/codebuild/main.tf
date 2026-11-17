data "aws_caller_identity" "current" {}

resource "aws_codebuild_project" "this" {
  name          = var.project_name
  description   = "Build and deploy the website to the EKS Fargate cluster."
  service_role  = var.codebuild_role_arn
  build_timeout = 30

  source {
    type            = "GITHUB"
    location        = var.repository_url
    git_clone_depth = 1
    buildspec       = var.buildspec_path

    auth {
      type     = "CODECONNECTIONS"
      resource = var.github_connection_arn
    }
  }

  source_version = var.repository_branch

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "${var.build_tools_repository_url}:${var.build_tools_image_tag}"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "SERVICE_ROLE"
    privileged_mode             = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }

    environment_variable {
      name  = "CLUSTER_NAME"
      value = var.eks_cluster_name
    }

    environment_variable {
      name  = "ECR_REPOSITORY_URI"
      value = var.ecr_repository_url
    }

    environment_variable {
      name  = "WEBSITE_NAMESPACE"
      value = "website"
    }

    environment_variable {
      name  = "WEEKLY_REPORT_ENABLED"
      value = tostring(var.enable_weekly_report)
    }
  }

  vpc_config {
    vpc_id             = var.vpc_id
    subnets            = var.private_subnet_ids
    security_group_ids = [var.codebuild_security_group_id]
  }

  logs_config {
    cloudwatch_logs {
      status     = "ENABLED"
      group_name = var.cloudwatch_log_group_name
    }

    s3_logs {
      status = "DISABLED"
    }
  }

}

resource "aws_codebuild_webhook" "this" {
  count = var.enable_github_webhook ? 1 : 0

  project_name = aws_codebuild_project.this.name
  build_type   = "BUILD"

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PUSH"
    }

    filter {
      type    = "HEAD_REF"
      pattern = "^refs/heads/main$"
    }
  }
}
