resource "aws_iam_openid_connect_provider" "eks" {
  url            = var.oidc_issuer_url
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "loki_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${trimprefix(var.oidc_issuer_url, "https://")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${trimprefix(var.oidc_issuer_url, "https://")}:sub"
      values   = ["system:serviceaccount:monitoring:loki"]
    }
  }
}

resource "aws_iam_role" "loki" {
  name               = "${var.project_name}-loki"
  assume_role_policy = data.aws_iam_policy_document.loki_assume_role.json
}

resource "aws_iam_role_policy" "loki" {
  name = "${var.project_name}-loki-s3"
  role = aws_iam_role.loki.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.bucket_arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${var.bucket_arn}/*"
      }
    ]
  })
}
