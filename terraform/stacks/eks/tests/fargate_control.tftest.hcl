mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_region" {
    defaults = {
      name = "ap-southeast-1"
    }
  }
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["ap-southeast-1a", "ap-southeast-1b"]
    }
  }
  mock_data "aws_eks_addon_version" {
    defaults = {
      version = "v1.0.0-eksbuild.1"
    }
  }
  mock_data "aws_ssm_parameter" {
    defaults = {
      type  = "String"
      value = "https://github.com/example/project"
    }
  }
}

mock_provider "archive" {}

override_data {
  target = data.terraform_remote_state.main
  values = {
    outputs = {
      eks_shared = {
        account_id                     = "123456789012"
        aws_region                     = "ap-southeast-1"
        project_name                   = "project"
        environment                    = "test"
        cluster_name                   = "project"
        website_repository_url         = "https://github.com/KFrost533/infra-eks-webhost"
        enable_fargate_control         = false
        eks_cluster_role_arn           = "arn:aws:iam::123456789012:role/eks"
        fargate_pod_execution_role_arn = "arn:aws:iam::123456789012:role/fargate"
        codebuild_role_arn             = "arn:aws:iam::123456789012:role/codebuild"
        codebuild_role_name            = "codebuild"
        github_oidc_provider_arn       = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
        codebuild_log_group_arn        = "arn:aws:logs:ap-southeast-1:123456789012:log-group:codebuild"
        codebuild_log_group_name       = "codebuild"
        fargate_log_group_name         = "fargate"
        fargate_control_log_group_name = "/aws/lambda/project-fargate-control"
        github_connection_arn          = "arn:aws:codeconnections:ap-southeast-1:123456789012:connection/test"
        ecr_repository_arn             = "arn:aws:ecr:ap-southeast-1:123456789012:repository/website"
        ecr_repository_url             = "123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/website"
        loki_bucket_arn                = "arn:aws:s3:::example-loki-logs"
        build_tools_repository_arn     = "arn:aws:ecr:ap-southeast-1:123456789012:repository/build-tools"
        build_tools_repository_url     = "123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/build-tools"
        fargate_control_role_arn       = null
        fargate_scheduler_role_arn     = null
        fargate_restore_role_arn       = null
        lambda_alerts_topic_arn        = null
      }
    }
  }
}

run "disabled_by_default" {
  command = plan

  assert {
    condition     = length(module.fargate_control) == 0
    error_message = "Fargate control must be opt-in."
  }
  assert {
    condition     = length(module.fargate_control_monitoring) == 0
    error_message = "Control monitoring must be disabled when Fargate control is disabled."
  }
  assert {
    condition     = var.enable_github_webhook == null
    error_message = "The EKS stack should use the CodeBuild module's webhook default."
  }
}

run "enable_control" {
  command = plan
  override_data {
    target = data.terraform_remote_state.main
    values = {
      outputs = {
        eks_shared = {
          account_id                     = "123456789012"
          aws_region                     = "ap-southeast-1"
          project_name                   = "project"
          environment                    = "test"
          cluster_name                   = "project"
          website_repository_url         = "https://github.com/KFrost533/infra-eks-webhost"
          enable_fargate_control         = true
          eks_cluster_role_arn           = "arn:aws:iam::123456789012:role/eks"
          fargate_pod_execution_role_arn = "arn:aws:iam::123456789012:role/fargate"
          codebuild_role_arn             = "arn:aws:iam::123456789012:role/codebuild"
          codebuild_role_name            = "codebuild"
          github_oidc_provider_arn       = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
          codebuild_log_group_arn        = "arn:aws:logs:ap-southeast-1:123456789012:log-group:codebuild"
          codebuild_log_group_name       = "codebuild"
          fargate_log_group_name         = "fargate"
          fargate_control_log_group_name = "/aws/lambda/project-fargate-control"
          github_connection_arn          = "arn:aws:codeconnections:ap-southeast-1:123456789012:connection/test"
          ecr_repository_arn             = "arn:aws:ecr:ap-southeast-1:123456789012:repository/website"
          ecr_repository_url             = "123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/website"
          loki_bucket_arn                = "arn:aws:s3:::example-loki-logs"
          build_tools_repository_arn     = "arn:aws:ecr:ap-southeast-1:123456789012:repository/build-tools"
          build_tools_repository_url     = "123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/build-tools"
          fargate_control_role_arn       = "arn:aws:iam::123456789012:role/fargate-control"
          fargate_scheduler_role_arn     = "arn:aws:iam::123456789012:role/scheduler"
          fargate_restore_role_arn       = "arn:aws:iam::123456789012:role/restore"
          lambda_alerts_topic_arn        = "arn:aws:sns:ap-southeast-1:123456789012:project-lambda-alerts"
        }
      }
    }
  }

  assert {
    condition     = module.fargate_control[0].function_name == "${local.shared.project_name}-fargate-control"
    error_message = "The Fargate control function was not created."
  }

  assert {
    condition     = var.enable_fargate_stop_schedule == null
    error_message = "The shutdown schedule must remain disabled until explicitly enabled."
  }

  assert {
    condition     = module.fargate_control_bus[0].rule_names == { stop = "${local.shared.project_name}-fargate-stop", restore = "${local.shared.project_name}-fargate-restore" }
    error_message = "The control bus must route stop and restore requests."
  }

  assert {
    condition     = length(module.fargate_control_monitoring) == 1 && output.lambda_alerts_topic_arn == local.shared.lambda_alerts_topic_arn
    error_message = "Lambda monitoring must use the shared SNS topic."
  }
}

run "lambda_monitoring" {
  command = plan
  module {
    source = "../../modules/eks/fargate-control/cloudwatch/alarm"
  }

  variables {
    function_name    = "project-fargate-control"
    log_group_name   = "/aws/lambda/project-fargate-control"
    sns_topic_arn    = "arn:aws:sns:ap-southeast-1:123456789012:project-lambda-alerts"
    event_bus_name   = "project-fargate-control"
    event_rule_names = { stop = "project-fargate-stop", restore = "project-fargate-restore" }
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.lambda_fargateControl_failure.pattern == "\"FARGATE_CONTROL_FAILURE\""
    error_message = "Application failure logs must feed the metric filter."
  }

  assert {
    condition     = toset(keys(aws_cloudwatch_metric_alarm.lambda)) == toset(["Errors", "Throttles", "AsyncEventsDropped"]) && length(aws_cloudwatch_metric_alarm.eventbridge) == 2
    error_message = "Lambda failures and both EventBridge delivery rules must be monitored."
  }

  assert {
    condition     = toset(aws_cloudwatch_composite_alarm.notification.alarm_actions) == toset([var.sns_topic_arn])
    error_message = "The composite alarm must notify the SNS topic."
  }
}

run "fargate_logs_enabled" {
  command = plan
  module {
    source = "../../modules/eks/fargate-control/cloudwatch/log"
  }

  variables {
    project_name           = "project"
    cluster_name           = "cluster"
    enable_fargate_control = true
  }

  assert {
    condition     = output.fargate_control_log_group_name == "/aws/lambda/project-fargate-control" && output.fargate_log_group_name == "/aws/eks/cluster/fargate"
    error_message = "The shared Fargate log module must expose the expected log groups."
  }
}

run "managed_codebuild_image" {
  command = plan
  module {
    source = "../../modules/common/codebuild"
  }
  variables {
    project_name                = "project"
    aws_region                  = "ap-southeast-2"
    github_connection_arn       = "arn:aws:codeconnections:ap-southeast-2:123456789012:connection/test"
    codebuild_role_arn          = "arn:aws:iam::123456789012:role/codebuild"
    vpc_id                      = "vpc-12345678"
    private_subnet_ids          = ["subnet-12345678"]
    codebuild_security_group_id = "sg-12345678"
    ecr_repository_url          = "123456789012.dkr.ecr.ap-southeast-2.amazonaws.com/website"
    eks_cluster_name            = "project"
    cloudwatch_log_group_name   = "/aws/codebuild/project"
  }

  assert {
    condition     = aws_codebuild_project.this.environment[0].image == "aws/codebuild/standard:7.0" && aws_codebuild_project.this.environment[0].image_pull_credentials_type == "CODEBUILD"
    error_message = "CodeBuild must use an AWS-managed image and CodeBuild credentials."
  }
  assert {
    condition     = aws_codebuild_project.this.source[0].location == "https://github.com/example/project" && aws_codebuild_project.this.source_version == "main" && aws_codebuild_project.this.source[0].auth[0].type == "CODECONNECTIONS"
    error_message = "CodeBuild must use the configured GitHub repository, branch, and connection."
  }
  assert {
    condition     = length(aws_codebuild_webhook.this) == 1 && toset([for filter in one(aws_codebuild_webhook.this[0].filter_group).filter : "${filter.type}:${filter.pattern}"]) == toset(["EVENT:PUSH", "HEAD_REF:^refs/heads/main$"])
    error_message = "The webhook must trigger only on pushes to main."
  }
}

run "webhook_disabled" {
  command = plan
  module {
    source = "../../modules/common/codebuild"
  }
  variables {
    project_name                = "project"
    aws_region                  = "ap-southeast-2"
    github_connection_arn       = "arn:aws:codeconnections:ap-southeast-2:123456789012:connection/test"
    repository_branch           = "main"
    buildspec_path              = "buildspec.yml"
    enable_github_webhook       = false
    codebuild_role_arn          = "arn:aws:iam::123456789012:role/codebuild"
    vpc_id                      = "vpc-12345678"
    private_subnet_ids          = ["subnet-12345678"]
    codebuild_security_group_id = "sg-12345678"
    ecr_repository_url          = "123456789012.dkr.ecr.ap-southeast-2.amazonaws.com/website"
    eks_cluster_name            = "project"
    cloudwatch_log_group_name   = "/aws/codebuild/project"
  }

  assert {
    condition     = length(aws_codebuild_webhook.this) == 0
    error_message = "The webhook must not be created when it is disabled."
  }
}

run "invalid_codebuild_repository_url" {
  command = plan
  module {
    source = "../../modules/common/codebuild"
  }
  variables {
    project_name                = "project"
    aws_region                  = "ap-southeast-2"
    github_connection_arn       = "arn:aws:codeconnections:ap-southeast-2:123456789012:connection/test"
    codebuild_role_arn          = "arn:aws:iam::123456789012:role/codebuild"
    vpc_id                      = "vpc-12345678"
    private_subnet_ids          = ["subnet-12345678"]
    codebuild_security_group_id = "sg-12345678"
    ecr_repository_url          = "123456789012.dkr.ecr.ap-southeast-2.amazonaws.com/website"
    eks_cluster_name            = "project"
    cloudwatch_log_group_name   = "/aws/codebuild/project"
  }
  override_data {
    target = data.aws_ssm_parameter.repository_url
    values = {
      type  = "String"
      value = "not-a-github-url"
    }
  }

  expect_failures = [aws_codebuild_project.this]
}

run "secure_codebuild_repository_url" {
  command = plan
  module {
    source = "../../modules/common/codebuild"
  }
  variables {
    project_name                = "project"
    aws_region                  = "ap-southeast-2"
    github_connection_arn       = "arn:aws:codeconnections:ap-southeast-2:123456789012:connection/test"
    codebuild_role_arn          = "arn:aws:iam::123456789012:role/codebuild"
    vpc_id                      = "vpc-12345678"
    private_subnet_ids          = ["subnet-12345678"]
    codebuild_security_group_id = "sg-12345678"
    ecr_repository_url          = "123456789012.dkr.ecr.ap-southeast-2.amazonaws.com/website"
    eks_cluster_name            = "project"
    cloudwatch_log_group_name   = "/aws/codebuild/project"
  }
  override_data {
    target = data.aws_ssm_parameter.repository_url
    values = {
      type  = "SecureString"
      value = "https://github.com/example/project"
    }
  }

  expect_failures = [aws_codebuild_project.this]
}

run "schedule_disabled_by_default" {
  command = plan
  module {
    source = "../../modules/eks/fargate-control/eventbridge"
  }
  variables {
    project_name       = "project"
    stop_alias_arn     = "arn:aws:lambda:ap-southeast-2:123456789012:function:project:stop"
    scheduler_role_arn = "arn:aws:iam::123456789012:role/scheduler"
  }
  assert {
    condition     = aws_scheduler_schedule.stop.state == "DISABLED"
    error_message = "The Fargate stop schedule must remain disabled by default."
  }
}
