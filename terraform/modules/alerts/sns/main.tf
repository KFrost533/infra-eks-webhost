data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_sns_topic" "lambda_alerts" {
  name = "${var.project_name}-lambda-alerts"
}

data "aws_iam_policy_document" "lambda_alerts" {
  statement {
    sid       = "AccountManagement"
    actions   = ["SNS:*"]
    resources = [aws_sns_topic.lambda_alerts.arn]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
  statement {
    sid       = "CloudWatchPublish"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.lambda_alerts.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudwatch:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:alarm:${var.project_name}-*"]
    }
  }
}

resource "aws_sns_topic_policy" "lambda_alerts" {
  arn    = aws_sns_topic.lambda_alerts.arn
  policy = data.aws_iam_policy_document.lambda_alerts.json
}
