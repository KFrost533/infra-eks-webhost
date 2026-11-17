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
}

mock_provider "archive" {}

variables {
  shared = {
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
    build_tools_repository_arn     = "arn:aws:ecr:ap-southeast-1:123456789012:repository/build-tools"
    build_tools_repository_url     = "123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/build-tools"
    fargate_control_role_arn       = null
    fargate_scheduler_role_arn     = null
    fargate_restore_role_arn       = null
    lambda_alerts_topic_arn        = null
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
}

run "enable_control" {
  command = plan
  variables {
    shared = {
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
      build_tools_repository_arn     = "arn:aws:ecr:ap-southeast-1:123456789012:repository/build-tools"
      build_tools_repository_url     = "123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/build-tools"
      fargate_control_role_arn       = "arn:aws:iam::123456789012:role/fargate-control"
      fargate_scheduler_role_arn     = "arn:aws:iam::123456789012:role/scheduler"
      fargate_restore_role_arn       = "arn:aws:iam::123456789012:role/restore"
      lambda_alerts_topic_arn        = "arn:aws:sns:ap-southeast-1:123456789012:project-lambda-alerts"
    }
  }

  assert {
    condition     = module.fargate_control[0].function_name == "${var.shared.project_name}-fargate-control"
    error_message = "The Fargate control function was not created."
  }

  assert {
    condition     = var.enable_fargate_stop_schedule == false
    error_message = "The shutdown schedule must remain disabled until explicitly enabled."
  }

  assert {
    condition     = module.fargate_control_bus[0].rule_names == { stop = "${var.shared.project_name}-fargate-stop", restore = "${var.shared.project_name}-fargate-restore" }
    error_message = "The control bus must route stop and restore requests."
  }

  assert {
    condition     = length(module.fargate_control_monitoring) == 1 && output.lambda_alerts_topic_arn == var.shared.lambda_alerts_topic_arn
    error_message = "Lambda monitoring must use the shared SNS topic."
  }
}

run "lambda_monitoring" {
  command = plan
  module {
    source = "../../modules/alerts/lambda"
  }
  variables {
    function_name    = "project-fargate-control"
    log_group_name   = "/aws/lambda/project-fargate-control"
    failure_pattern  = "\"FARGATE_CONTROL_FAILURE\""
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
