mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_region" {
    defaults = {
      name = "ap-southeast-2"
    }
  }
}

run "loki_archive" {
  command = plan
  module {
    source = "../../modules/common/s3"
  }
  variables {
    project_name = "project"
  }

  assert {
    condition = toset(flatten([
      for rule in aws_s3_bucket_lifecycle_configuration.loki_logs.rule : [
        for transition in rule.transition : "${transition.days}:${transition.storage_class}"
      ]
    ])) == toset(["30:GLACIER_IR", "120:DEEP_ARCHIVE"])
    error_message = "Loki objects must transition at 30 and 120 days."
  }
  assert {
    condition     = alltrue([for rule in aws_s3_bucket_lifecycle_configuration.loki_logs.rule : length(rule.expiration) == 0])
    error_message = "Loki objects must not expire automatically."
  }
}
